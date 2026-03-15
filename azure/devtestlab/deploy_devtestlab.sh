#!/bin/bash
# =============================================================================
# deploy_devtestlab.sh — Déploiement OFPPT-Lab via Azure DevTest Labs
# =============================================================================
# Alternative au déploiement Terraform/Azure CLI classique.
# Azure DevTest Labs apporte :
#   - Arrêt automatique des VMs (économies de coût)
#   - Quotas par stagiaire (max VMs, tailles autorisées)
#   - Self-service : les stagiaires créent leurs propres VMs
#   - Formules : templates pré-configurés pour chaque filière
#   - Artefacts : installation automatisée des outils de TP
#   - Intégration Moodle / Azure DevOps possible
#
# USAGE :
#   ./deploy_devtestlab.sh deploy          # Déployer le lab complet
#   ./deploy_devtestlab.sh create-vms      # Créer les VMs de démo (formateur)
#   ./deploy_devtestlab.sh status          # Voir l'état du lab
#   ./deploy_devtestlab.sh policies        # Appliquer/mettre à jour les politiques
#   ./deploy_devtestlab.sh destroy         # Supprimer toute l'infrastructure
# =============================================================================

set -euo pipefail

# ── Couleurs ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; MAGENTA='\033[0;35m'; NC='\033[0m'; BOLD='\033[1m'

log()     { echo -e "${GREEN}[DTL]${NC}  $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERREUR]${NC} $1"; exit 1; }
info()    { echo -e "${CYAN}[INFO]${NC} $1"; }
section() { echo -e "\n${BLUE}${BOLD}╔══ $1 ══╗${NC}"; }

# ── Configuration ─────────────────────────────────────────────────────────────
RESOURCE_GROUP="rg-ofppt-devtestlab"
LOCATION="francecentral"
LAB_NAME="ofppt-lab-formation"
ADMIN_USER="azureofppt"
SSH_KEY_FILE="$HOME/.ssh/ofppt_azure.pub"

# Tailles de VMs autorisées dans le lab
VM_SIZE_CLOUD="Standard_D4s_v3"    # 4 vCPU, 16 GB — Docker, K8s, Terraform
VM_SIZE_RESEAU="Standard_D2s_v3"   # 2 vCPU,  8 GB — réseau, routage
VM_SIZE_CYBER="Standard_D4s_v3"    # 4 vCPU, 16 GB — Metasploit, outils offensifs

# Repo d'artefacts (ce dépôt GitHub)
ARTIFACT_REPO_URL="https://github.com/votre-org/ofppt-lab"
ARTIFACT_REPO_BRANCH="master"
ARTIFACT_REPO_FOLDER="/azure/devtestlab/artifacts"

# Politiques du lab
AUTO_SHUTDOWN_TIME="2359"          # Filet de sécurité (arrêt durée géré par Automation)
AUTO_SHUTDOWN_TZ="Romance Standard Time"
MAX_VMS_PER_USER=3                 # Quota par stagiaire (3 filières possibles)
MAX_VMS_PER_LAB=30                 # Quota total du lab
OS_DISK_GB=128

# Arrêt par durée — Azure Automation
AUTOMATION_ACCOUNT="aa-ofppt-lab-duration"
MAX_DURATION_HOURS=4               # Arrêt automatique après 4h de fonctionnement
RUNBOOK_NAME="Stop-DTL-VMs-By-Duration"
RUNBOOK_FILE="$(dirname "$0")/runbook_stop_by_duration.ps1"
SCHEDULE_INTERVAL_MINUTES=15       # Vérification toutes les 15 minutes

# Tags
TAGS="Environment=Lab Project=OFPPT-Lab Owner=Formation ManagedBy=DevTestLabs"

# ── Vérifications préalables ──────────────────────────────────────────────────
check_prerequisites() {
    section "Vérification des prérequis"

    command -v az &>/dev/null || error "Azure CLI non installé. Voir : https://aka.ms/InstallAzureCLI"
    az account show &>/dev/null || { warn "Non connecté — lancement de az login..."; az login; }

    local ACCOUNT SUB_ID
    ACCOUNT=$(az account show --query name -o tsv)
    SUB_ID=$(az account show --query id -o tsv)
    log "Compte Azure : ${BOLD}$ACCOUNT${NC}"
    log "Subscription : $SUB_ID"

    # Vérifier l'extension DevTest Labs
    if ! az extension show --name azure-devops &>/dev/null 2>&1; then
        info "Extension DevTest Labs non nécessaire (commandes az lab intégrées)"
    fi

    # Clé SSH
    if [[ ! -f "$SSH_KEY_FILE" ]]; then
        warn "Clé SSH absente, génération en cours..."
        ssh-keygen -t rsa -b 4096 -f "${SSH_KEY_FILE%.pub}" -N "" -C "ofppt-devtestlab"
        log "Clé SSH créée : $SSH_KEY_FILE"
    fi
    log "Clé SSH : $SSH_KEY_FILE"
}

# ── Resource Group ────────────────────────────────────────────────────────────
create_resource_group() {
    section "Resource Group"

    if az group show --name "$RESOURCE_GROUP" &>/dev/null; then
        warn "Resource Group '$RESOURCE_GROUP' existe déjà, on continue."
    else
        az group create \
            --name "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --tags $TAGS \
            --output table
        log "Resource Group '$RESOURCE_GROUP' créé dans $LOCATION"
    fi
}

# ── Création du Lab DevTest Labs ──────────────────────────────────────────────
create_lab() {
    section "Création du Lab Azure DevTest Labs"

    if az lab show --resource-group "$RESOURCE_GROUP" --name "$LAB_NAME" &>/dev/null; then
        warn "Lab '$LAB_NAME' existe déjà."
    else
        az lab create \
            --resource-group "$RESOURCE_GROUP" \
            --name "$LAB_NAME" \
            --location "$LOCATION" \
            --tags $TAGS \
            --output table
        log "Lab '${BOLD}$LAB_NAME${NC}' créé"
    fi

    # URL du lab
    local LAB_URL
    LAB_URL="https://portal.azure.com/#resource/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.DevTestLab/labs/$LAB_NAME"
    info "URL du Lab (portail Azure) : $LAB_URL"
}

# ── Politiques du Lab ─────────────────────────────────────────────────────────
configure_policies() {
    section "Configuration des politiques du Lab"

    # 1. Arrêt automatique des VMs
    log "Politique : arrêt automatique à $AUTO_SHUTDOWN_TIME ($AUTO_SHUTDOWN_TZ)"
    az lab policy set \
        --resource-group "$RESOURCE_GROUP" \
        --lab-name "$LAB_NAME" \
        --policy-set-name "default" \
        --name "GalleryImage" \
        --status "Disabled" \
        --output none 2>/dev/null || true

    # Configurer l'arrêt automatique via le lab schedule
    az lab schedule create \
        --resource-group "$RESOURCE_GROUP" \
        --lab-name "$LAB_NAME" \
        --name "LabVmsShutdown" \
        --status "Enabled" \
        --time "$AUTO_SHUTDOWN_TIME" \
        --time-zone-id "$AUTO_SHUTDOWN_TZ" \
        --task-type "LabVmsShutdownTask" \
        --output table 2>/dev/null || \
    az lab schedule update \
        --resource-group "$RESOURCE_GROUP" \
        --lab-name "$LAB_NAME" \
        --name "LabVmsShutdown" \
        --status "Enabled" \
        --time "$AUTO_SHUTDOWN_TIME" \
        --output none 2>/dev/null || warn "Mise à jour du schedule ignorée (déjà configuré)"
    log "Arrêt automatique configuré : $AUTO_SHUTDOWN_TIME"

    # 2. Quota VMs par utilisateur
    log "Politique : max $MAX_VMS_PER_USER VM(s) par stagiaire"
    az lab policy set \
        --resource-group "$RESOURCE_GROUP" \
        --lab-name "$LAB_NAME" \
        --policy-set-name "default" \
        --name "MaxVmsAllowedPerUser" \
        --status "Enabled" \
        --threshold "$MAX_VMS_PER_USER" \
        --fact-name "UserOwnedLabVmCount" \
        --evaluator-type "MaxValuePolicy" \
        --output table

    # 3. Quota VMs total du lab
    log "Politique : max $MAX_VMS_PER_LAB VMs au total dans le lab"
    az lab policy set \
        --resource-group "$RESOURCE_GROUP" \
        --lab-name "$LAB_NAME" \
        --policy-set-name "default" \
        --name "MaxVmsAllowedPerLab" \
        --status "Enabled" \
        --threshold "$MAX_VMS_PER_LAB" \
        --fact-name "LabVmCount" \
        --evaluator-type "MaxValuePolicy" \
        --output table

    # 4. Tailles de VMs autorisées (filtrage des coûts)
    log "Politique : tailles de VMs autorisées"
    az lab policy set \
        --resource-group "$RESOURCE_GROUP" \
        --lab-name "$LAB_NAME" \
        --policy-set-name "default" \
        --name "AllowedVmSizesInLab" \
        --status "Enabled" \
        --threshold "[\"Standard_B2s\",\"Standard_B4ms\",\"Standard_D2s_v3\",\"Standard_D4s_v3\"]" \
        --fact-name "LabVmSize" \
        --evaluator-type "AllowedValuesPolicy" \
        --output table

    # 5. Interdire les IPs publiques (accès via Guacamole uniquement)
    log "Politique : IPs publiques désactivées par défaut"
    az lab policy set \
        --resource-group "$RESOURCE_GROUP" \
        --lab-name "$LAB_NAME" \
        --policy-set-name "default" \
        --name "AllowedPublicIpAddress" \
        --status "Enabled" \
        --threshold "Shared" \
        --fact-name "LabVmPresence" \
        --evaluator-type "AllowedValuesPolicy" \
        --output none 2>/dev/null || warn "Politique IP publique ignorée (optionnelle)"

    log "Politiques configurées avec succès"
}

# ── Référentiel d'artefacts ───────────────────────────────────────────────────
register_artifact_repo() {
    section "Enregistrement du référentiel d'artefacts"

    # Vérifier si le repo GitHub est public ou générer un PAT
    warn "Assurez-vous que le repo GitHub est public OU que vous avez un Personal Access Token."
    info "Pour un repo privé, exporter : export GITHUB_PAT='votre-token'"

    local SEC_TOKEN="${GITHUB_PAT:-}"

    if [[ -n "$SEC_TOKEN" ]]; then
        az lab artifact-source create \
            --resource-group "$RESOURCE_GROUP" \
            --lab-name "$LAB_NAME" \
            --name "ofppt-artifacts" \
            --display-name "OFPPT Lab Artifacts" \
            --uri "$ARTIFACT_REPO_URL" \
            --source-type "GitHub" \
            --folder-path "$ARTIFACT_REPO_FOLDER" \
            --branch-ref "$ARTIFACT_REPO_BRANCH" \
            --security-token "$SEC_TOKEN" \
            --output table
        log "Référentiel d'artefacts enregistré (repo privé)"
    else
        az lab artifact-source create \
            --resource-group "$RESOURCE_GROUP" \
            --lab-name "$LAB_NAME" \
            --name "ofppt-artifacts" \
            --display-name "OFPPT Lab Artifacts" \
            --uri "$ARTIFACT_REPO_URL" \
            --source-type "GitHub" \
            --folder-path "$ARTIFACT_REPO_FOLDER" \
            --branch-ref "$ARTIFACT_REPO_BRANCH" \
            --output table 2>/dev/null || warn "Repo public sans PAT — artefacts publics uniquement"
        log "Référentiel d'artefacts enregistré (repo public)"
    fi
}

# ── Formules de VMs (templates réutilisables) ─────────────────────────────────
create_formulas() {
    section "Création des formules de VMs"

    local SSH_KEY
    SSH_KEY=$(cat "$SSH_KEY_FILE")

    # ── Formule : VM Cloud Computing ──────────────────────────────────────
    log "Formule : vm-cloud-computing"
    az lab formula create \
        --resource-group "$RESOURCE_GROUP" \
        --lab-name "$LAB_NAME" \
        --name "OFPPT-Cloud-Computing" \
        --description "VM filière Cloud Computing — Docker, Terraform, kubectl, Azure CLI, Ansible" \
        --os-type "Linux" \
        --formula-content "{
            \"properties\": {
                \"description\": \"VM filière Cloud Computing OFPPT\",
                \"labVirtualMachineCreationParameter\": {
                    \"size\": \"$VM_SIZE_CLOUD\",
                    \"userName\": \"$ADMIN_USER\",
                    \"sshKey\": \"$SSH_KEY\",
                    \"isAuthenticationWithSshKey\": true,
                    \"labSubnetName\": \"Subnet\",
                    \"disallowPublicIpAddress\": false,
                    \"storageType\": \"Premium\",
                    \"osDiskSizeGiB\": $OS_DISK_GB,
                    \"galleryImageReference\": {
                        \"offer\": \"0001-com-ubuntu-server-jammy\",
                        \"publisher\": \"Canonical\",
                        \"sku\": \"22_04-lts-gen2\",
                        \"osType\": \"Linux\",
                        \"version\": \"latest\"
                    },
                    \"artifacts\": [
                        {
                            \"artifactId\": \"/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.DevTestLab/labs/$LAB_NAME/artifactSources/ofppt-artifacts/artifacts/cloud-tools\",
                            \"artifactTitle\": \"OFPPT Cloud Tools\"
                        }
                    ],
                    \"notes\": \"Cloud Computing — Docker CE, Terraform 1.7, kubectl, Azure CLI, AWS CLI, Ansible, Minikube\"
                }
            }
        }" \
        --output table 2>/dev/null || warn "Formule cloud déjà existante ou erreur mineure"
    log "Formule 'OFPPT-Cloud-Computing' créée"

    # ── Formule : VM Réseau & Infrastructure ──────────────────────────────
    log "Formule : vm-reseau-infrastructure"
    az lab formula create \
        --resource-group "$RESOURCE_GROUP" \
        --lab-name "$LAB_NAME" \
        --name "OFPPT-Reseau-Infrastructure" \
        --description "VM filière Réseau — Wireshark, FRRouting, OpenVPN, WireGuard, Open vSwitch" \
        --os-type "Linux" \
        --formula-content "{
            \"properties\": {
                \"description\": \"VM filière Réseau & Infrastructure OFPPT\",
                \"labVirtualMachineCreationParameter\": {
                    \"size\": \"$VM_SIZE_RESEAU\",
                    \"userName\": \"$ADMIN_USER\",
                    \"sshKey\": \"$SSH_KEY\",
                    \"isAuthenticationWithSshKey\": true,
                    \"labSubnetName\": \"Subnet\",
                    \"disallowPublicIpAddress\": false,
                    \"storageType\": \"Premium\",
                    \"osDiskSizeGiB\": $OS_DISK_GB,
                    \"galleryImageReference\": {
                        \"offer\": \"0001-com-ubuntu-server-jammy\",
                        \"publisher\": \"Canonical\",
                        \"sku\": \"22_04-lts-gen2\",
                        \"osType\": \"Linux\",
                        \"version\": \"latest\"
                    },
                    \"artifacts\": [
                        {
                            \"artifactId\": \"/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.DevTestLab/labs/$LAB_NAME/artifactSources/ofppt-artifacts/artifacts/reseau-tools\",
                            \"artifactTitle\": \"OFPPT Réseau Tools\"
                        }
                    ],
                    \"notes\": \"Réseau — Wireshark, tcpdump, Nmap, FRRouting (OSPF/BGP), OpenVPN, WireGuard, OVS\"
                }
            }
        }" \
        --output table 2>/dev/null || warn "Formule réseau déjà existante ou erreur mineure"
    log "Formule 'OFPPT-Reseau-Infrastructure' créée"

    # ── Formule : VM Cybersécurité ─────────────────────────────────────────
    log "Formule : vm-cybersecurite"
    az lab formula create \
        --resource-group "$RESOURCE_GROUP" \
        --lab-name "$LAB_NAME" \
        --name "OFPPT-Cybersecurite" \
        --description "VM filière Cybersécurité — Metasploit, Nmap, Burp Suite, DVWA, Volatility" \
        --os-type "Linux" \
        --formula-content "{
            \"properties\": {
                \"description\": \"VM filière Cybersécurité OFPPT\",
                \"labVirtualMachineCreationParameter\": {
                    \"size\": \"$VM_SIZE_CYBER\",
                    \"userName\": \"$ADMIN_USER\",
                    \"sshKey\": \"$SSH_KEY\",
                    \"isAuthenticationWithSshKey\": true,
                    \"labSubnetName\": \"Subnet\",
                    \"disallowPublicIpAddress\": false,
                    \"storageType\": \"Premium\",
                    \"osDiskSizeGiB\": $OS_DISK_GB,
                    \"galleryImageReference\": {
                        \"offer\": \"0001-com-ubuntu-server-jammy\",
                        \"publisher\": \"Canonical\",
                        \"sku\": \"22_04-lts-gen2\",
                        \"osType\": \"Linux\",
                        \"version\": \"latest\"
                    },
                    \"artifacts\": [
                        {
                            \"artifactId\": \"/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.DevTestLab/labs/$LAB_NAME/artifactSources/ofppt-artifacts/artifacts/cyber-tools\",
                            \"artifactTitle\": \"OFPPT Cyber Tools\"
                        }
                    ],
                    \"notes\": \"Cybersécurité — Metasploit, Nmap, Burp Suite, sqlmap, Hydra, Volatility, DVWA\"
                }
            }
        }" \
        --output table 2>/dev/null || warn "Formule cyber déjà existante ou erreur mineure"
    log "Formule 'OFPPT-Cybersecurite' créée"
}

# ── Création des VMs de démonstration (formateur) ────────────────────────────
create_demo_vms() {
    section "Création des VMs de démonstration (formateur)"

    warn "Cette section crée des VMs pour le formateur uniquement."
    warn "Les stagiaires utiliseront le self-service du portail DevTest Labs."

    local SSH_KEY
    SSH_KEY=$(cat "$SSH_KEY_FILE")

    local VMS=(
        "vm-cloud-demo:$VM_SIZE_CLOUD:cloud-tools:Cloud Computing"
        "vm-reseau-demo:$VM_SIZE_RESEAU:reseau-tools:Réseau Infrastructure"
        "vm-cyber-demo:$VM_SIZE_CYBER:cyber-tools:Cybersécurité"
    )

    for VM_ENTRY in "${VMS[@]}"; do
        IFS=':' read -r VM_NAME VM_SIZE ARTIFACT VM_LABEL <<< "$VM_ENTRY"
        log "Création de la VM de démo : $VM_NAME ($VM_LABEL)"

        az lab vm create \
            --resource-group "$RESOURCE_GROUP" \
            --lab-name "$LAB_NAME" \
            --name "$VM_NAME" \
            --size "$VM_SIZE" \
            --image "Ubuntu Server 22.04 LTS" \
            --image-type "Gallery" \
            --user-name "$ADMIN_USER" \
            --ssh-key "$SSH_KEY" \
            --os-disk-size "$OS_DISK_GB" \
            --storage-type "Premium" \
            --output table \
        && log "VM '$VM_NAME' créée dans le lab" \
        || warn "VM '$VM_NAME' : erreur ou déjà existante"
    done
}

# ── Ajouter des utilisateurs au lab (stagiaires) ─────────────────────────────
add_lab_users() {
    section "Gestion des utilisateurs (stagiaires)"

    local SUBSCRIPTION_ID
    SUBSCRIPTION_ID=$(az account show --query id -o tsv)
    local LAB_SCOPE="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.DevTestLab/labs/$LAB_NAME"

    info "Pour ajouter des stagiaires au lab, utiliser la commande suivante :"
    echo ""
    echo -e "  ${CYAN}az role assignment create \\${NC}"
    echo -e "    ${CYAN}--assignee <email-stagiaire@ofppt.ma> \\${NC}"
    echo -e "    ${CYAN}--role 'DevTest Labs User' \\${NC}"
    echo -e "    ${CYAN}--scope '$LAB_SCOPE'${NC}"
    echo ""
    info "Le rôle 'DevTest Labs User' permet aux stagiaires de :"
    echo "  - Créer leurs propres VMs depuis les formules disponibles"
    echo "  - Démarrer/arrêter leurs VMs"
    echo "  - Pas d'accès aux paramètres du lab"
    echo ""

    # Vérifier si une liste d'utilisateurs est passée en argument
    if [[ -n "${USERS_FILE:-}" && -f "$USERS_FILE" ]]; then
        log "Ajout des utilisateurs depuis $USERS_FILE"
        while IFS= read -r EMAIL; do
            [[ -z "$EMAIL" || "$EMAIL" == "#"* ]] && continue
            az role assignment create \
                --assignee "$EMAIL" \
                --role "DevTest Labs User" \
                --scope "$LAB_SCOPE" \
                --output none \
            && log "  Stagiaire ajouté : $EMAIL" \
            || warn "  Impossible d'ajouter : $EMAIL"
        done < "$USERS_FILE"
    fi
}

# ── Activer la gestion des coûts ─────────────────────────────────────────────
configure_cost_management() {
    section "Gestion des coûts"

    info "Activation du suivi des coûts du lab..."
    az lab cost create \
        --resource-group "$RESOURCE_GROUP" \
        --lab-name "$LAB_NAME" \
        --target-cost "{
            \"status\": \"Enabled\",
            \"target\": 100,
            \"costThresholds\": [
                {
                    \"thresholdId\": \"threshold-50\",
                    \"percentageThreshold\": { \"thresholdValue\": 50 },
                    \"displayOnChart\": \"Enabled\",
                    \"sendAlertWhenExceeded\": \"Enabled\"
                },
                {
                    \"thresholdId\": \"threshold-80\",
                    \"percentageThreshold\": { \"thresholdValue\": 80 },
                    \"displayOnChart\": \"Enabled\",
                    \"sendAlertWhenExceeded\": \"Enabled\"
                }
            ],
            \"cycleType\": \"CalendarMonth\",
            \"cycleStartDateTime\": \"$(date -u +%Y-%m-01T00:00:00.000Z)\",
            \"cycleEndDateTime\": \"$(date -u +%Y-%m-28T23:59:59.000Z)\"
        }" \
        --output none 2>/dev/null || warn "Gestion des coûts : configuration manuelle dans le portail Azure recommandée"

    log "Coût cible : 100 USD/mois avec alertes à 50% et 80%"
}

# ── Résumé et informations d'accès ───────────────────────────────────────────
show_summary() {
    section "Résumé du Lab OFPPT DevTest Labs"

    local SUBSCRIPTION_ID
    SUBSCRIPTION_ID=$(az account show --query id -o tsv)

    echo ""
    echo -e "  ${BOLD}Lab Azure DevTest Labs${NC}"
    echo -e "  ├─ Nom          : ${GREEN}$LAB_NAME${NC}"
    echo -e "  ├─ Région       : $LOCATION"
    echo -e "  ├─ Groupe       : $RESOURCE_GROUP"
    echo ""
    echo -e "  ${BOLD}Formules disponibles (templates VMs)${NC}"
    echo -e "  ├─ ${CYAN}OFPPT-Cloud-Computing${NC}       (${VM_SIZE_CLOUD})"
    echo -e "  ├─ ${CYAN}OFPPT-Reseau-Infrastructure${NC}  (${VM_SIZE_RESEAU})"
    echo -e "  └─ ${CYAN}OFPPT-Cybersecurite${NC}         (${VM_SIZE_CYBER})"
    echo ""
    echo -e "  ${BOLD}Politiques actives${NC}"
    echo -e "  ├─ Arrêt par durée : ${YELLOW}${MAX_DURATION_HOURS}h max${NC} (Azure Automation — toutes les ${SCHEDULE_INTERVAL_MINUTES} min)"
    echo -e "  ├─ Filet sécurité  : ${YELLOW}23h59${NC} (arrêt fixe DTL en dernier recours)"
    echo -e "  ├─ VMs/stagiaire   : ${YELLOW}max $MAX_VMS_PER_USER${NC}"
    echo -e "  └─ VMs totales     : ${YELLOW}max $MAX_VMS_PER_LAB${NC}"
    echo ""
    echo -e "  ${BOLD}Portail Self-Service stagiaires :${NC}"
    echo -e "  ${MAGENTA}https://labs.azure.com${NC}"
    echo ""
    echo -e "  ${BOLD}URL Azure Portal :${NC}"
    echo -e "  ${MAGENTA}https://portal.azure.com/#resource/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.DevTestLab/labs/$LAB_NAME${NC}"
    echo ""
    echo -e "  ${BOLD}Comparatif des méthodes de déploiement :${NC}"
    printf "  %-28s %-12s %-12s %-12s\n" "Fonctionnalité" "Vagrant" "Terraform" "DevTest Labs"
    printf "  %-28s %-12s %-12s %-12s\n" "────────────────────────────" "────────────" "────────────" "────────────"
    printf "  %-28s %-12s %-12s %-12s\n" "Arrêt automatique"      "❌ Manuel"  "❌ Manuel"  "✅ Natif"
    printf "  %-28s %-12s %-12s %-12s\n" "Quotas par stagiaire"   "❌"          "❌"          "✅ Intégré"
    printf "  %-28s %-12s %-12s %-12s\n" "Self-service stagiaires" "❌"          "❌"          "✅ Portail"
    printf "  %-28s %-12s %-12s %-12s\n" "Gestion des coûts"      "N/A"         "❌ Manuel"  "✅ Natif"
    printf "  %-28s %-12s %-12s %-12s\n" "Cloud natif"            "❌ Local"    "✅"           "✅"
    printf "  %-28s %-12s %-12s %-12s\n" "IaC (reproductible)"    "✅ Vagrant"  "✅ Terraform" "✅ ARM/CLI"
    echo ""
    echo -e "  ${YELLOW}Pour supprimer le lab :${NC}"
    echo -e "  ${RED}az group delete --name $RESOURCE_GROUP --yes --no-wait${NC}"
    echo ""
}

# ── Azure Automation — Arrêt par durée ───────────────────────────────────────
setup_automation() {
    section "Azure Automation — Arrêt par durée (${MAX_DURATION_HOURS}h)"

    local SUBSCRIPTION_ID
    SUBSCRIPTION_ID=$(az account show --query id -o tsv)

    # 1. Créer l'Automation Account
    log "Création de l'Automation Account : $AUTOMATION_ACCOUNT"
    az automation account create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$AUTOMATION_ACCOUNT" \
        --location "$LOCATION" \
        --sku "Basic" \
        --tags $TAGS \
        --output table 2>/dev/null || warn "Automation Account déjà existant"
    log "Automation Account '$AUTOMATION_ACCOUNT' prêt"

    # 2. Activer la Managed Identity (System-Assigned)
    log "Activation de la Managed Identity (System-Assigned)..."
    az automation account update \
        --resource-group "$RESOURCE_GROUP" \
        --name "$AUTOMATION_ACCOUNT" \
        --set identity.type=SystemAssigned \
        --output none 2>/dev/null || warn "Managed Identity déjà activée"

    local PRINCIPAL_ID
    PRINCIPAL_ID=$(az automation account show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$AUTOMATION_ACCOUNT" \
        --query identity.principalId -o tsv 2>/dev/null)
    log "Principal ID (Managed Identity) : $PRINCIPAL_ID"

    # 3. Attribuer le rôle Contributor sur le Resource Group
    log "Attribution du rôle 'Contributor' sur le Resource Group..."
    az role assignment create \
        --assignee-object-id "$PRINCIPAL_ID" \
        --assignee-principal-type ServicePrincipal \
        --role "Contributor" \
        --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP" \
        --output none 2>/dev/null || warn "Rôle déjà attribué"
    log "Rôle Contributor attribué"

    # 4. Importer le module Az.Accounts dans l'Automation Account
    log "Import du module Az.Accounts (nécessaire pour Connect-AzAccount)..."
    az automation module create \
        --resource-group "$RESOURCE_GROUP" \
        --automation-account-name "$AUTOMATION_ACCOUNT" \
        --name "Az.Accounts" \
        --content-link "https://www.powershellgallery.com/api/v2/package/Az.Accounts" \
        --output none 2>/dev/null || warn "Module Az.Accounts déjà importé"

    az automation module create \
        --resource-group "$RESOURCE_GROUP" \
        --automation-account-name "$AUTOMATION_ACCOUNT" \
        --name "Az.Resources" \
        --content-link "https://www.powershellgallery.com/api/v2/package/Az.Resources" \
        --output none 2>/dev/null || warn "Module Az.Resources déjà importé"

    az automation module create \
        --resource-group "$RESOURCE_GROUP" \
        --automation-account-name "$AUTOMATION_ACCOUNT" \
        --name "Az.Monitor" \
        --content-link "https://www.powershellgallery.com/api/v2/package/Az.Monitor" \
        --output none 2>/dev/null || warn "Module Az.Monitor déjà importé"
    log "Modules Az importés (import asynchrone — attendre 1-2 min)"

    # 5. Créer le Runbook PowerShell
    log "Création du Runbook : $RUNBOOK_NAME"
    [[ -f "$RUNBOOK_FILE" ]] || error "Fichier runbook introuvable : $RUNBOOK_FILE"

    az automation runbook create \
        --resource-group "$RESOURCE_GROUP" \
        --automation-account-name "$AUTOMATION_ACCOUNT" \
        --name "$RUNBOOK_NAME" \
        --type "PowerShell" \
        --description "Arrête les VMs DTL après ${MAX_DURATION_HOURS}h de fonctionnement" \
        --output none 2>/dev/null || warn "Runbook déjà existant"

    # 6. Publier le contenu du runbook
    log "Publication du contenu du runbook..."
    az automation runbook replace-content \
        --resource-group "$RESOURCE_GROUP" \
        --automation-account-name "$AUTOMATION_ACCOUNT" \
        --name "$RUNBOOK_NAME" \
        --content @"$RUNBOOK_FILE" \
        --output none

    az automation runbook publish \
        --resource-group "$RESOURCE_GROUP" \
        --automation-account-name "$AUTOMATION_ACCOUNT" \
        --name "$RUNBOOK_NAME" \
        --output none
    log "Runbook publié avec succès"

    # 7. Créer le planning toutes les N minutes
    log "Création du planning : toutes les ${SCHEDULE_INTERVAL_MINUTES} minutes..."
    local SCHEDULE_NAME="schedule-every-${SCHEDULE_INTERVAL_MINUTES}min"
    local START_TIME
    START_TIME=$(date -u -d "+2 minutes" '+%Y-%m-%dT%H:%M:%S+00:00' 2>/dev/null || \
                 python3 -c "from datetime import datetime,timedelta; print((datetime.utcnow()+timedelta(minutes=2)).strftime('%Y-%m-%dT%H:%M:%S+00:00'))")

    az automation schedule create \
        --resource-group "$RESOURCE_GROUP" \
        --automation-account-name "$AUTOMATION_ACCOUNT" \
        --name "$SCHEDULE_NAME" \
        --frequency "Minute" \
        --interval "$SCHEDULE_INTERVAL_MINUTES" \
        --start-time "$START_TIME" \
        --description "Vérification durée VMs toutes les ${SCHEDULE_INTERVAL_MINUTES} min" \
        --output none 2>/dev/null || warn "Planning déjà existant"

    # 8. Lier le planning au runbook avec les paramètres
    log "Association du planning au runbook..."
    az automation job-schedule create \
        --resource-group "$RESOURCE_GROUP" \
        --automation-account-name "$AUTOMATION_ACCOUNT" \
        --runbook-name "$RUNBOOK_NAME" \
        --schedule-name "$SCHEDULE_NAME" \
        --parameters \
            ResourceGroupName="$RESOURCE_GROUP" \
            LabName="$LAB_NAME" \
            MaxDurationHours="$MAX_DURATION_HOURS" \
            DryRun="false" \
        --output none 2>/dev/null || warn "Association planning/runbook déjà existante"

    log ""
    log "✅ Automation configurée avec succès :"
    log "   Runbook     : $RUNBOOK_NAME"
    log "   Planning    : toutes les $SCHEDULE_INTERVAL_MINUTES min"
    log "   Durée max   : $MAX_DURATION_HOURS heures"
    log "   Cible       : lab '$LAB_NAME'"
    info "Les VMs seront arrêtées automatiquement après ${MAX_DURATION_HOURS}h de fonctionnement"
}

# ── Test du runbook en mode Dry Run ──────────────────────────────────────────
test_automation() {
    section "Test du Runbook (Dry Run)"

    log "Lancement d'un job de test (DryRun=true — aucune VM ne sera arrêtée)..."
    local JOB_ID
    JOB_ID=$(az automation job create \
        --resource-group "$RESOURCE_GROUP" \
        --automation-account-name "$AUTOMATION_ACCOUNT" \
        --runbook-name "$RUNBOOK_NAME" \
        --parameters \
            ResourceGroupName="$RESOURCE_GROUP" \
            LabName="$LAB_NAME" \
            MaxDurationHours="$MAX_DURATION_HOURS" \
            DryRun="true" \
        --query name -o tsv)
    log "Job lancé : $JOB_ID"
    info "Voir les logs : az automation job stream list --resource-group $RESOURCE_GROUP --automation-account-name $AUTOMATION_ACCOUNT --job-name $JOB_ID --stream-type Output --query '[].value' -o tsv"
}

# ── Destruction du lab ────────────────────────────────────────────────────────
destroy_lab() {
    section "Suppression du Lab Azure DevTest Labs"

    warn "⚠  Cette action va SUPPRIMER le lab et TOUTES ses VMs !"
    echo -ne "  Tapez 'CONFIRMER' pour continuer : "
    read -r CONFIRM
    [[ "$CONFIRM" == "CONFIRMER" ]] || { log "Opération annulée."; exit 0; }

    log "Suppression du Resource Group '$RESOURCE_GROUP' en cours..."
    az group delete \
        --name "$RESOURCE_GROUP" \
        --yes \
        --no-wait
    log "Suppression lancée en arrière-plan (peut prendre 5-10 min)."
}

# ── Lister les VMs actives dans le lab ───────────────────────────────────────
list_lab_vms() {
    section "VMs actives dans le lab"

    az lab vm list \
        --resource-group "$RESOURCE_GROUP" \
        --lab-name "$LAB_NAME" \
        --query "[].{Nom:name, Taille:size, Statut:provisioningState, OS:storageType}" \
        --output table 2>/dev/null || warn "Aucune VM ou lab introuvable"
}

# ── Point d'entrée ────────────────────────────────────────────────────────────
case "${1:-deploy}" in
    deploy)
        check_prerequisites
        create_resource_group
        create_lab
        configure_policies
        register_artifact_repo
        create_formulas
        configure_cost_management
        setup_automation          # ← Arrêt par durée (4h)
        add_lab_users
        show_summary
        ;;
    create-vms)
        check_prerequisites
        create_demo_vms
        list_lab_vms
        ;;
    policies)
        check_prerequisites
        configure_policies
        ;;
    automation)
        # Déployer ou mettre à jour uniquement l'Automation
        check_prerequisites
        setup_automation
        ;;
    test-automation)
        # Tester le runbook sans arrêter de VMs
        check_prerequisites
        test_automation
        ;;
    status)
        check_prerequisites
        show_summary
        list_lab_vms
        ;;
    add-users)
        # Usage: USERS_FILE=stagiaires.txt ./deploy_devtestlab.sh add-users
        check_prerequisites
        add_lab_users
        ;;
    destroy)
        check_prerequisites
        destroy_lab
        ;;
    *)
        echo ""
        echo -e "  ${BOLD}OFPPT-Lab — Déploiement Azure DevTest Labs${NC}"
        echo ""
        echo -e "  Usage: $0 {deploy|create-vms|policies|automation|test-automation|status|add-users|destroy}"
        echo ""
        echo -e "  ${CYAN}deploy${NC}            Déployer le lab complet (Lab + Politiques + Formules + Automation)"
        echo -e "  ${CYAN}create-vms${NC}        Créer les VMs de démonstration (formateur)"
        echo -e "  ${CYAN}policies${NC}          Appliquer/mettre à jour les politiques du lab"
        echo -e "  ${CYAN}automation${NC}        Déployer/mettre à jour l'arrêt par durée (${MAX_DURATION_HOURS}h)"
        echo -e "  ${CYAN}test-automation${NC}   Tester le runbook sans arrêter de VMs (Dry Run)"
        echo -e "  ${CYAN}status${NC}            Voir l'état du lab et ses VMs"
        echo -e "  ${CYAN}add-users${NC}         Ajouter des stagiaires (USERS_FILE=liste.txt)"
        echo -e "  ${CYAN}destroy${NC}           Supprimer l'infrastructure complète"
        echo ""
        exit 1
        ;;
esac
