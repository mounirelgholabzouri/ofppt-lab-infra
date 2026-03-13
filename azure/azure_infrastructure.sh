#!/bin/bash
# =============================================================================
# azure_infrastructure.sh — Déploiement infrastructure Azure OFPPT-Lab
# =============================================================================
# Déploie l'infrastructure Azure complète pour OFPPT-Lab :
#   - Resource Group, Virtual Network, Subnets
#   - VM Moodle (serveur pédagogique)
#   - VM Guacamole (passerelle d'accès)
#   - VM Lab (environnements TP)
#   - NSG, Load Balancer, DNS
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'; BOLD='\033[1m'

log()     { echo -e "${GREEN}[AZURE]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
section() { echo -e "\n${BLUE}${BOLD}━━━ $1 ━━━${NC}"; }

# ── Variables de configuration ────────────────────────────────────────────────
RESOURCE_GROUP="rg-ofppt-lab"
LOCATION="westeurope"
VNET_NAME="vnet-ofppt"
VNET_PREFIX="10.0.0.0/16"
SUBNET_WEB="subnet-web"
SUBNET_LAB="subnet-lab"
SUBNET_MGMT="subnet-mgmt"
PREFIX_WEB="10.0.1.0/24"
PREFIX_LAB="10.0.2.0/24"
PREFIX_MGMT="10.0.3.0/24"

# VMs
VM_MOODLE_NAME="vm-moodle"
VM_GUAC_NAME="vm-guacamole"
VM_LAB_NAME="vm-lab"
VM_SIZE_WEB="Standard_B2s"     # 2 vCPU, 4 GB RAM
VM_SIZE_LAB="Standard_D4s_v3"  # 4 vCPU, 16 GB RAM
OS_IMAGE="Ubuntu2204"
ADMIN_USER="azureofppt"
SSH_KEY_FILE="$HOME/.ssh/ofppt_azure.pub"

# Tags communs
TAGS="Environment=Lab Project=OFPPT Owner=Mounir"

# ════════════════════════════════════════════════════════
# VÉRIFICATIONS PRÉALABLES
# ════════════════════════════════════════════════════════
check_prerequisites() {
    section "Vérification des prérequis"
    command -v az &>/dev/null || error "Azure CLI non installé. Lancer : curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash"
    az account show &>/dev/null || { warn "Non connecté à Azure. Lancement de az login..."; az login; }
    log "Azure CLI connecté : $(az account show --query name -o tsv)"
    # Générer clé SSH si absente
    if [[ ! -f "$SSH_KEY_FILE" ]]; then
        ssh-keygen -t rsa -b 4096 -f "${SSH_KEY_FILE%.pub}" -N "" -C "ofppt-azure"
        log "Clé SSH générée : $SSH_KEY_FILE"
    fi
}

# ════════════════════════════════════════════════════════
# RESOURCE GROUP
# ════════════════════════════════════════════════════════
create_resource_group() {
    section "Création du Resource Group"
    az group create \
        --name "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --tags $TAGS \
        --output table
    log "Resource Group '$RESOURCE_GROUP' créé dans $LOCATION"
}

# ════════════════════════════════════════════════════════
# RÉSEAU VIRTUEL & SOUS-RÉSEAUX
# ════════════════════════════════════════════════════════
create_network() {
    section "Création du réseau virtuel"
    az network vnet create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$VNET_NAME" \
        --address-prefix "$VNET_PREFIX" \
        --subnet-name "$SUBNET_WEB" \
        --subnet-prefix "$PREFIX_WEB" \
        --tags $TAGS \
        --output table
    log "VNet '$VNET_NAME' créé ($VNET_PREFIX)"

    # Sous-réseaux supplémentaires
    for SUBNET in "$SUBNET_LAB:$PREFIX_LAB" "$SUBNET_MGMT:$PREFIX_MGMT"; do
        SNAME="${SUBNET%%:*}"; SPREFIX="${SUBNET##*:}"
        az network vnet subnet create \
            --resource-group "$RESOURCE_GROUP" \
            --vnet-name "$VNET_NAME" \
            --name "$SNAME" \
            --address-prefix "$SPREFIX" \
            --output table
        log "Sous-réseau '$SNAME' créé ($SPREFIX)"
    done
}

# ════════════════════════════════════════════════════════
# NETWORK SECURITY GROUPS
# ════════════════════════════════════════════════════════
create_nsg() {
    section "Création des Network Security Groups"

    # NSG pour le sous-réseau Web (Moodle + Guacamole)
    az network nsg create \
        --resource-group "$RESOURCE_GROUP" \
        --name "nsg-web" \
        --tags $TAGS --output table

    # Règles NSG Web
    local RULES_WEB=(
        "Allow-SSH:100:Tcp:22:*"
        "Allow-HTTP:110:Tcp:80:*"
        "Allow-HTTPS:120:Tcp:443:*"
        "Allow-Guac:130:Tcp:8080:*"
    )
    for RULE in "${RULES_WEB[@]}"; do
        IFS=':' read -r NAME PRIO PROTO PORT SOURCE <<< "$RULE"
        az network nsg rule create \
            --resource-group "$RESOURCE_GROUP" \
            --nsg-name "nsg-web" \
            --name "$NAME" \
            --priority "$PRIO" \
            --protocol "$PROTO" \
            --destination-port-range "$PORT" \
            --source-address-prefix "$SOURCE" \
            --access Allow --direction Inbound \
            --output none
        log "  Règle NSG-Web : $NAME (port $PORT)"
    done

    # NSG pour le sous-réseau Lab
    az network nsg create \
        --resource-group "$RESOURCE_GROUP" \
        --name "nsg-lab" \
        --tags $TAGS --output table

    az network nsg rule create \
        --resource-group "$RESOURCE_GROUP" \
        --nsg-name "nsg-lab" \
        --name "Allow-Internal" \
        --priority 100 \
        --source-address-prefix "$VNET_PREFIX" \
        --destination-port-range "*" \
        --access Allow --direction Inbound \
        --output none
    log "NSGs créés : nsg-web, nsg-lab"
}

# ════════════════════════════════════════════════════════
# IPs PUBLIQUES
# ════════════════════════════════════════════════════════
create_public_ips() {
    section "Création des IPs publiques"
    for VM in "$VM_MOODLE_NAME" "$VM_GUAC_NAME"; do
        az network public-ip create \
            --resource-group "$RESOURCE_GROUP" \
            --name "pip-${VM}" \
            --sku Standard \
            --allocation-method Static \
            --dns-name "${VM}-ofppt" \
            --tags $TAGS \
            --output table
        local IP
        IP=$(az network public-ip show \
            --resource-group "$RESOURCE_GROUP" \
            --name "pip-${VM}" \
            --query ipAddress -o tsv)
        log "IP publique pour $VM : $IP"
    done
}

# ════════════════════════════════════════════════════════
# MACHINES VIRTUELLES
# ════════════════════════════════════════════════════════
create_vm() {
    local VM_NAME="$1" SUBNET="$2" SIZE="$3" NSG="$4" PIP_SUFFIX="$5"
    local HAS_PIP="${PIP_SUFFIX:-}"

    log "Création de la VM : $VM_NAME ($SIZE)"
    local PIP_ARGS=""
    [[ -n "$HAS_PIP" ]] && PIP_ARGS="--public-ip-address pip-${VM_NAME}"

    az vm create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$VM_NAME" \
        --image "$OS_IMAGE" \
        --size "$SIZE" \
        --admin-username "$ADMIN_USER" \
        --ssh-key-values "$SSH_KEY_FILE" \
        --vnet-name "$VNET_NAME" \
        --subnet "$SUBNET" \
        --nsg "$NSG" \
        $PIP_ARGS \
        --storage-sku Premium_LRS \
        --os-disk-size-gb 64 \
        --tags $TAGS \
        --output table

    log "✅ VM '$VM_NAME' créée"
}

create_vms() {
    section "Création des machines virtuelles"
    create_vm "$VM_MOODLE_NAME" "$SUBNET_WEB"  "$VM_SIZE_WEB" "nsg-web" "yes"
    create_vm "$VM_GUAC_NAME"   "$SUBNET_WEB"  "$VM_SIZE_WEB" "nsg-web" "yes"
    create_vm "$VM_LAB_NAME"    "$SUBNET_LAB"  "$VM_SIZE_LAB" "nsg-lab" ""
}

# ════════════════════════════════════════════════════════
# PROVISIONNEMENT DES VMs
# ════════════════════════════════════════════════════════
provision_vms() {
    section "Provisionnement des VMs"

    # Moodle
    log "Provisionnement Moodle..."
    az vm run-command invoke \
        --resource-group "$RESOURCE_GROUP" \
        --name "$VM_MOODLE_NAME" \
        --command-id RunShellScript \
        --scripts @../moodle/install_moodle.sh \
        --output table
    log "Moodle installé"

    # Guacamole
    log "Provisionnement Guacamole..."
    az vm run-command invoke \
        --resource-group "$RESOURCE_GROUP" \
        --name "$VM_GUAC_NAME" \
        --command-id RunShellScript \
        --scripts @../guacamole/install_guacamole.sh \
        --output table
    log "Guacamole installé"
}

# ════════════════════════════════════════════════════════
# AFFICHAGE DU RÉSUMÉ
# ════════════════════════════════════════════════════════
show_summary() {
    section "Résumé de l'infrastructure"
    echo ""
    echo -e "  ${BOLD}Resource Group :${NC} $RESOURCE_GROUP ($LOCATION)"
    echo -e "  ${BOLD}Réseau VNet    :${NC} $VNET_NAME ($VNET_PREFIX)"
    echo ""
    echo -e "  ${BOLD}VMs déployées :${NC}"

    for VM in "$VM_MOODLE_NAME" "$VM_GUAC_NAME" "$VM_LAB_NAME"; do
        local IP
        IP=$(az vm show -d -g "$RESOURCE_GROUP" -n "$VM" \
             --query publicIps -o tsv 2>/dev/null || echo "N/A")
        local PRIVATE_IP
        PRIVATE_IP=$(az vm show -d -g "$RESOURCE_GROUP" -n "$VM" \
             --query privateIps -o tsv 2>/dev/null || echo "N/A")
        echo -e "    ${GREEN}●${NC} ${BOLD}$VM${NC}"
        echo -e "      IP publique  : ${YELLOW}$IP${NC}"
        echo -e "      IP privée    : ${CYAN}$PRIVATE_IP${NC}"
    done

    echo ""
    log "Infrastructure OFPPT-Lab déployée sur Azure ✅"
    echo -e "  ${YELLOW}Coût estimé : ~30-50 USD/mois (arrêtez les VMs si non utilisées)${NC}"
    echo ""
    echo -e "  ${BOLD}Pour supprimer TOUTE l'infrastructure :${NC}"
    echo -e "  ${RED}az group delete --name $RESOURCE_GROUP --yes${NC}"
}

# ════════════════════════════════════════════════════════
# DESTRUCTION (cleanup)
# ════════════════════════════════════════════════════════
destroy_infrastructure() {
    warn "⚠  Cette action va SUPPRIMER TOUTE l'infrastructure Azure !"
    echo -ne "  Tapez 'CONFIRMER' pour continuer : "
    read -r CONFIRM
    [[ "$CONFIRM" == "CONFIRMER" ]] || { log "Opération annulée."; exit 0; }
    az group delete --name "$RESOURCE_GROUP" --yes --no-wait
    log "Suppression du resource group lancée en arrière-plan."
}

# ════════════════════════════════════════════════════════
# POINT D'ENTRÉE
# ════════════════════════════════════════════════════════
case "${1:-deploy}" in
    deploy)
        check_prerequisites
        create_resource_group
        create_network
        create_nsg
        create_public_ips
        create_vms
        provision_vms
        show_summary
        ;;
    destroy)
        check_prerequisites
        destroy_infrastructure
        ;;
    status)
        check_prerequisites
        show_summary
        ;;
    *)
        echo "Usage: $0 {deploy|destroy|status}"
        exit 1
        ;;
esac
