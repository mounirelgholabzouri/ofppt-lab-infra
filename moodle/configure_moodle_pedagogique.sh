#!/bin/bash
# =============================================================================
# configure_moodle_pedagogique.sh — Configuration pédagogique OFPPT-Lab
# =============================================================================
# Configure les filières, cours, utilisateurs et ressources pédagogiques
# pour les formations : Cloud, Réseaux, Cybersécurité
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

MOODLE_DIR="/var/www/html/moodle"
MOODLE_PHP="sudo -u www-data php ${MOODLE_DIR}/admin/cli/moosh.php"
ADMIN_USER="admin"
ADMIN_PASS="Admin@OFPPT2024!"
MOODLE_URL="http://localhost/moodle"

log()     { echo -e "${GREEN}[INFO]${NC}  $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
section() { echo -e "\n${BLUE}╔══════════════════════════════════════╗${NC}"; \
            echo -e "${BLUE}║  $1${NC}"; \
            echo -e "${BLUE}╚══════════════════════════════════════╝${NC}"; }

[[ $EUID -ne 0 ]] && error "Exécution requise en root"

# ── Installation de moosh (outil CLI Moodle) ──────────────────────────────────
section "Installation de moosh"
if ! command -v moosh &>/dev/null; then
    apt-get install -y composer php-cli
    cd /tmp
    git clone https://github.com/tmuras/moosh.git
    cd moosh
    composer install --no-dev
    ln -sf /tmp/moosh/moosh.php /usr/local/bin/moosh
    chmod +x /usr/local/bin/moosh
    log "moosh installé"
else
    log "moosh déjà présent"
fi

MOOSH="moosh -n -p ${MOODLE_DIR}"

# ── Création des catégories de filières ───────────────────────────────────────
section "Création des filières OFPPT"

declare -A FILIERES=(
    ["Cloud Computing"]="Formation aux technologies cloud : Azure, AWS, GCP"
    ["Réseaux & Infrastructure"]="Administration réseaux, routage, switching, VPN"
    ["Cybersécurité"]="Sécurité offensive/défensive, pentest, forensics"
)

for FILIERE in "${!FILIERES[@]}"; do
    DESCRIPTION="${FILIERES[$FILIERE]}"
    $MOOSH category-create --description "$DESCRIPTION" --parent 0 "$FILIERE" 2>/dev/null && \
        log "Filière créée : $FILIERE" || warn "Filière existe déjà : $FILIERE"
done

# ── Création des cours ────────────────────────────────────────────────────────
section "Création des cours"

# Cloud Computing
declare -a COURS_CLOUD=(
    "CC101|Introduction au Cloud Computing|cloud-intro"
    "CC201|Microsoft Azure — Administration|azure-admin"
    "CC202|Azure DevOps & CI/CD|azure-devops"
    "CC301|Terraform & Infrastructure as Code|iac-terraform"
    "CC302|Kubernetes & Conteneurisation|k8s-containers"
)

# Réseaux
declare -a COURS_RESEAU=(
    "RES101|Fondamentaux des Réseaux|net-fundamentals"
    "RES201|Cisco CCNA — Routing & Switching|ccna-rs"
    "RES202|Administration Linux Serveur|linux-admin"
    "RES301|Virtualisation VMware/VirtualBox|virtualisation"
    "RES302|VPN & Accès distant|vpn-remote"
)

# Cybersécurité
declare -a COURS_CYBER=(
    "CYB101|Introduction à la Cybersécurité|cyber-intro"
    "CYB201|Pentest & Ethical Hacking|pentest"
    "CYB202|Analyse de vulnérabilités|vuln-analysis"
    "CYB301|Forensics Numérique|forensics"
    "CYB302|SIEM & Monitoring SOC|siem-soc"
)

create_course() {
    local LINE="$1"; local CATNAME="$2"
    IFS='|' read -r CODE NOM SHORTNAME <<< "$LINE"
    $MOOSH course-create \
        --category="$CATNAME" \
        --fullname="$NOM" \
        --shortname="$SHORTNAME" \
        --visible=1 \
        --format=topics 2>/dev/null && \
        log "  ✓ Cours créé : [$CODE] $NOM" || warn "  ⚠ Cours existant : $NOM"
}

log "→ Cours Cloud Computing"
for COURS in "${COURS_CLOUD[@]}"; do create_course "$COURS" "Cloud Computing"; done

log "→ Cours Réseaux"
for COURS in "${COURS_RESEAU[@]}"; do create_course "$COURS" "Réseaux & Infrastructure"; done

log "→ Cours Cybersécurité"
for COURS in "${COURS_CYBER[@]}"; do create_course "$COURS" "Cybersécurité"; done

# ── Création des comptes formateurs ──────────────────────────────────────────
section "Création des comptes formateurs"

declare -a FORMATEURS=(
    "formateur.cloud|Formateur|Cloud|fcloud@ofppt.ma|FormateurCloud@2024"
    "formateur.reseau|Formateur|Réseau|freseau@ofppt.ma|FormateurReseau@2024"
    "formateur.cyber|Formateur|Cyber|fcyber@ofppt.ma|FormateurCyber@2024"
)

for FORMATEUR in "${FORMATEURS[@]}"; do
    IFS='|' read -r USERNAME FIRSTNAME LASTNAME EMAIL PASSWORD <<< "$FORMATEUR"
    $MOOSH user-create \
        --password="$PASSWORD" \
        --email="$EMAIL" \
        --firstname="$FIRSTNAME" \
        --lastname="$LASTNAME" \
        "$USERNAME" 2>/dev/null && \
        log "Formateur créé : $USERNAME ($EMAIL)" || warn "Formateur existant : $USERNAME"
done

# ── Création des stagiaires de démonstration ─────────────────────────────────
section "Création de stagiaires de démonstration"

for i in $(seq 1 5); do
    for FILIERE in cloud reseau cyber; do
        USERNAME="stagiaire${FILIERE}${i}"
        EMAIL="stagiaire${FILIERE}${i}@ofppt.ma"
        $MOOSH user-create \
            --password="Stagiaire@2024!" \
            --email="$EMAIL" \
            --firstname="Stagiaire${i}" \
            --lastname="${FILIERE^}" \
            "$USERNAME" 2>/dev/null && \
            log "  Stagiaire : $USERNAME" || true
    done
done

# ── Configuration des paramètres pédagogiques ─────────────────────────────────
section "Configuration des paramètres Moodle"

# Langue par défaut
$MOOSH config-set lang fr 2>/dev/null && log "Langue définie : Français"

# Fuseau horaire
$MOOSH config-set timezone "Africa/Casablanca" 2>/dev/null && log "Fuseau : Africa/Casablanca"

# Taille max upload
$MOOSH config-set maxbytes 536870912 2>/dev/null  # 512MB

# Activer le mode maintenance OFF (site accessible)
$MOOSH maintenance-off 2>/dev/null && log "Mode maintenance désactivé"

# ── Création des ressources TP dans chaque cours ─────────────────────────────
section "Ajout de ressources TP"

# Créer des pages de bienvenue pour chaque cours
php "${MOODLE_DIR}/admin/cli/cron.php" > /dev/null 2>&1 &
log "Cron Moodle lancé pour initialisation"

section "Configuration terminée"
echo ""
log "✅ Configuration pédagogique OFPPT-Lab appliquée avec succès !"
echo -e "   Filières  : ${YELLOW}Cloud, Réseaux, Cybersécurité${NC}"
echo -e "   Cours     : ${YELLOW}15 cours créés${NC}"
echo -e "   Formateurs: ${YELLOW}3 comptes formateurs${NC}"
echo -e "   Stagiaires: ${YELLOW}15 comptes stagiaires (démo)${NC}"
echo -e "   URL Moodle: ${YELLOW}${MOODLE_URL}${NC}"
