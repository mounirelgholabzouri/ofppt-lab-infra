#!/bin/bash
# =============================================================================
# install.sh — Installation de l'intégration DevTest Labs sur le serveur Moodle
# =============================================================================
# Exécuter en tant que root sur la VM Moodle :
#   sudo bash install.sh
# =============================================================================

set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'; BOLD='\033[1m'
log()  { echo -e "${GREEN}[INSTALL]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC}   $1"; }
err()  { echo -e "${RED}[ERREUR]${NC} $1"; exit 1; }

MOODLE_ROOT="${MOODLE_ROOT:-/var/www/html/moodle}"
WEB_USER="${WEB_USER:-www-data}"
INSTALL_DIR="$MOODLE_ROOT/local/devtestlab"
LOG_FILE="/var/log/ofppt-devtestlab.log"

echo ""
echo -e "${BOLD}═══ OFPPT Academy — Installation intégration DevTest Labs ═══${NC}"
echo ""

# ── Vérifications ─────────────────────────────────────────────────────────────
[[ -d "$MOODLE_ROOT" ]]        || err "Moodle introuvable dans $MOODLE_ROOT"
command -v php  &>/dev/null    || err "PHP non installé"
command -v curl &>/dev/null    || err "curl non installé"

PHP_VERSION=$(php -r 'echo PHP_MAJOR_VERSION . "." . PHP_MINOR_VERSION;')
log "PHP détecté : $PHP_VERSION"
log "Moodle root : $MOODLE_ROOT"

# ── Copie des fichiers ────────────────────────────────────────────────────────
log "Création du répertoire $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cp -v "$SCRIPT_DIR/config.php"                  "$INSTALL_DIR/"
cp -v "$SCRIPT_DIR/azure_dtl_api.php"           "$INSTALL_DIR/"
cp -v "$SCRIPT_DIR/launch_tp.php"               "$INSTALL_DIR/"
cp -v "$SCRIPT_DIR/status.php"                  "$INSTALL_DIR/"
cp -v "$SCRIPT_DIR/setup_moodle_activities.php" "$INSTALL_DIR/"

chown -R "$WEB_USER:$WEB_USER" "$INSTALL_DIR"
chmod 750 "$INSTALL_DIR"
chmod 640 "$INSTALL_DIR"/*.php
log "Fichiers copiés dans $INSTALL_DIR"

# ── Fichier de log ────────────────────────────────────────────────────────────
touch "$LOG_FILE"
chown "$WEB_USER:$WEB_USER" "$LOG_FILE"
chmod 640 "$LOG_FILE"
log "Fichier de log : $LOG_FILE"

# ── Variables d'environnement ─────────────────────────────────────────────────
ENV_FILE="/etc/ofppt-devtestlab.env"
if [[ ! -f "$ENV_FILE" ]]; then
    cat > "$ENV_FILE" << 'EOF'
# =============================================================
# Variables d'environnement — Intégration OFPPT DevTest Labs
# Remplir les valeurs avant de démarrer Apache
# =============================================================
AZURE_TENANT_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
AZURE_CLIENT_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
AZURE_CLIENT_SECRET=votre-secret-azure
AZURE_SUBSCRIPTION_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
MOODLE_WWWROOT=https://moodle.ofppt-academy.ma
TP_SECRET_KEY=ofppt-tp-changer-cette-cle-en-production
EOF
    chmod 600 "$ENV_FILE"
    warn "⚠  Remplir $ENV_FILE avec vos vraies valeurs Azure !"
else
    log "Fichier .env déjà présent : $ENV_FILE"
fi

# ── Charger les variables dans Apache ────────────────────────────────────────
APACHE_ENV="/etc/apache2/envvars"
if grep -q "AZURE_TENANT_ID" "$APACHE_ENV" 2>/dev/null; then
    log "Variables Apache déjà configurées"
else
    echo "" >> "$APACHE_ENV"
    echo "# OFPPT DevTest Labs Integration" >> "$APACHE_ENV"
    echo ". $ENV_FILE" >> "$APACHE_ENV"
    log "Variables ajoutées dans $APACHE_ENV"
    warn "Redémarrez Apache après avoir rempli $ENV_FILE"
fi

# ── Extension PHP cURL ────────────────────────────────────────────────────────
if php -m | grep -q curl; then
    log "Extension PHP curl : OK"
else
    warn "Extension PHP curl manquante — installation..."
    apt-get install -y "php${PHP_VERSION}-curl" || warn "Installer manuellement php-curl"
fi

# ── Lien symbolique dans Moodle (accès via /local/devtestlab/) ───────────────
MOODLE_LOCAL="$MOODLE_ROOT/local/devtestlab"
if [[ -d "$MOODLE_LOCAL" && "$MOODLE_LOCAL" != "$INSTALL_DIR" ]]; then
    log "Répertoire local Moodle déjà présent : $MOODLE_LOCAL"
fi

# ── Création des activités Moodle ─────────────────────────────────────────────
echo ""
log "Création des activités 'Lancer le TP' dans Moodle..."
sudo -u "$WEB_USER" php "$INSTALL_DIR/setup_moodle_activities.php" || \
    warn "setup_moodle_activities.php : à relancer manuellement si des cours n'existent pas encore"

# ── Résumé ────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}══════════════════════════════════════════════════${NC}"
echo -e "  ${GREEN}✅ Installation terminée !${NC}"
echo -e "══════════════════════════════════════════════════"
echo ""
echo -e "  ${BOLD}Étapes suivantes :${NC}"
echo -e "  1. Remplir ${CYAN}$ENV_FILE${NC} avec vos credentials Azure"
echo -e "  2. Redémarrer Apache : ${CYAN}systemctl restart apache2${NC}"
echo -e "  3. Tester en ouvrant la page Moodle d'un cours TP"
echo ""
echo -e "  ${BOLD}URL du lanceur TP :${NC}"
echo -e "  ${CYAN}https://moodle.ofppt-academy.ma/local/devtestlab/launch_tp.php?tp=CC101-TP1${NC}"
echo ""
echo -e "  ${BOLD}Logs :${NC} tail -f $LOG_FILE"
echo ""
