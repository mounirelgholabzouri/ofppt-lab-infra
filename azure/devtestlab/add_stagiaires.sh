#!/bin/bash
# =============================================================================
# add_stagiaires.sh — Enrôlement des stagiaires dans Azure DevTest Labs
# =============================================================================
# Usage :
#   ./add_stagiaires.sh                          # Mode interactif
#   ./add_stagiaires.sh --csv stagiaires.csv     # Depuis fichier CSV
#   ./add_stagiaires.sh --email user@ofppt.ma    # Un seul stagiaire
#
# Format CSV (sans entête) :
#   email,prenom,nom,filiere
#   ali.hassan@ofppt.ma,Ali,Hassan,cloud
#   fatima.zahra@ofppt.ma,Fatima,Zahra,cyber
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

log()     { echo -e "${GREEN}[DTL]${NC}  $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERR]${NC}  $1"; exit 1; }
section() { echo -e "\n${CYAN}${BOLD}── $1 ──${NC}"; }

AZ="C:/Program Files/Microsoft SDKs/Azure/CLI2/wbin/az.cmd"
RESOURCE_GROUP="rg-ofppt-devtestlab"
LAB_NAME="ofppt-lab-formation"
SUBSCRIPTION_ID=""
LAB_SCOPE=""
ADDED=0; SKIPPED=0; FAILED=0

# ── Récupérer l'ID de subscription ───────────────────────────────────────────
init() {
    SUBSCRIPTION_ID=$("$AZ" account show --query id -o tsv 2>/dev/null) \
        || error "Non connecté à Azure. Lancer : az login"
    LAB_SCOPE="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.DevTestLab/labs/$LAB_NAME"
    log "Subscription : $SUBSCRIPTION_ID"
    log "Lab scope    : $LAB_SCOPE"
}

# ── Ajouter un stagiaire ──────────────────────────────────────────────────────
add_user() {
    local EMAIL="$1"
    local LABEL="${2:-$EMAIL}"

    # Vérifier si le rôle est déjà attribué
    local EXISTING
    EXISTING=$("$AZ" role assignment list \
        --assignee "$EMAIL" \
        --role "DevTest Labs User" \
        --scope "$LAB_SCOPE" \
        --query "length(@)" -o tsv 2>/dev/null || echo "0")

    if [[ "$EXISTING" -gt 0 ]]; then
        warn "  Déjà enrôlé : $LABEL"
        ((SKIPPED++))
        return
    fi

    "$AZ" role assignment create \
        --assignee "$EMAIL" \
        --role "DevTest Labs User" \
        --scope "$LAB_SCOPE" \
        --output none 2>/dev/null \
    && { log "  ✅ Ajouté : $LABEL"; ((ADDED++)); } \
    || { warn "  ❌ Échec  : $LABEL (compte Azure AD inexistant ?)"; ((FAILED++)); }
}

# ── Depuis fichier CSV ────────────────────────────────────────────────────────
from_csv() {
    local FILE="$1"
    [[ -f "$FILE" ]] || error "Fichier introuvable : $FILE"
    section "Enrôlement depuis $FILE"

    while IFS=',' read -r EMAIL PRENOM NOM FILIERE || [[ -n "$EMAIL" ]]; do
        [[ -z "$EMAIL" || "$EMAIL" == "#"* ]] && continue
        EMAIL=$(echo "$EMAIL" | tr -d '[:space:]')
        LABEL="$PRENOM $NOM ($FILIERE)"
        add_user "$EMAIL" "$LABEL"
    done < "$FILE"
}

# ── Un seul stagiaire ─────────────────────────────────────────────────────────
from_single() {
    local EMAIL="$1"
    section "Ajout du stagiaire $EMAIL"
    add_user "$EMAIL"
}

# ── Mode interactif ───────────────────────────────────────────────────────────
interactive() {
    section "Mode interactif — Ajout de stagiaires"
    echo ""
    echo "  Entrez les emails des stagiaires (un par ligne)."
    echo "  Ligne vide pour terminer."
    echo ""

    while true; do
        echo -ne "  Email stagiaire (ou Entrée pour terminer) : "
        read -r EMAIL
        [[ -z "$EMAIL" ]] && break
        add_user "$EMAIL"
    done
}

# ── Lister les stagiaires actuels ─────────────────────────────────────────────
list_users() {
    section "Stagiaires enrôlés dans le lab"
    "$AZ" role assignment list \
        --scope "$LAB_SCOPE" \
        --role "DevTest Labs User" \
        --query "[].{Email:principalName, Role:roleDefinitionName}" \
        --output table 2>/dev/null || warn "Aucun stagiaire enrôlé"
}

# ── Créer un fichier CSV exemple ──────────────────────────────────────────────
create_sample_csv() {
    cat > stagiaires_exemple.csv << 'CSV'
# Format : email,prenom,nom,filiere
# Filières : cloud | reseau | cyber
ali.hassan@ofppt.ma,Ali,Hassan,cloud
fatima.zahra@ofppt.ma,Fatima,Zahra,cyber
youssef.benali@ofppt.ma,Youssef,Benali,reseau
aicha.mansouri@ofppt.ma,Aicha,Mansouri,cloud
CSV
    log "Fichier exemple créé : stagiaires_exemple.csv"
}

# ── Résumé ────────────────────────────────────────────────────────────────────
show_summary() {
    section "Résumé"
    echo -e "  ${GREEN}✅ Ajoutés  : $ADDED${NC}"
    echo -e "  ${YELLOW}⏭  Ignorés  : $SKIPPED${NC} (déjà enrôlés)"
    echo -e "  ${RED}❌ Échecs   : $FAILED${NC}"
    echo ""
    echo -e "  ${BOLD}Les stagiaires peuvent accéder au lab sur :${NC}"
    echo -e "  ${CYAN}https://labs.azure.com${NC}"
    echo ""
    echo -e "  ${BOLD}Portail Azure DevTest Labs :${NC}"
    echo -e "  ${CYAN}https://portal.azure.com/#resource/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.DevTestLab/labs/$LAB_NAME${NC}"
}

# ── Point d'entrée ────────────────────────────────────────────────────────────
init

case "${1:---interactive}" in
    --csv)       from_csv    "${2:-}" ;;
    --email)     from_single "${2:-}" ;;
    --list)      list_users; exit 0 ;;
    --sample)    create_sample_csv; exit 0 ;;
    --interactive) interactive ;;
    *) echo "Usage: $0 [--csv fichier.csv | --email email | --list | --sample]"; exit 1 ;;
esac

show_summary
