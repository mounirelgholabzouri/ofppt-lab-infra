#!/bin/bash
# =============================================================================
# deploy_prod.sh — Déploiement intégration DevTest Labs sur serveur Moodle PROD
# =============================================================================
# Usage :
#   sudo bash deploy_prod.sh
#
# Variables d'environnement requises (ou saisies interactivement) :
#   AZURE_CLIENT_SECRET  — secret du Service Principal sp-ofppt-moodle-dtl
#   MOODLE_WWWROOT       — ex: https://moodle.ofppt-academy.ma
#   MOODLE_ROOT          — ex: /var/www/html/moodle (défaut)
#   WEB_USER             — ex: www-data (défaut)
#
# Exemple :
#   AZURE_CLIENT_SECRET='xxx' MOODLE_WWWROOT='https://moodle.ofppt-academy.ma' \
#     sudo -E bash deploy_prod.sh
# =============================================================================

set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
log()  { echo -e "${GREEN}[DEPLOY]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC}   $1"; }
err()  { echo -e "${RED}[ERREUR]${NC} $1"; exit 1; }

# ── Valeurs prod connues (non-secrètes) ───────────────────────────────────────
AZURE_TENANT_ID="${AZURE_TENANT_ID:-687d3cdf-7038-4560-a9f5-b3f0403eb863}"
AZURE_CLIENT_ID="${AZURE_CLIENT_ID:-ae328530-c971-44a9-98dc-443f0618b4fc}"
AZURE_SUBSCRIPTION_ID="${AZURE_SUBSCRIPTION_ID:-b64ddf59-d9cf-4c48-8174-27962dfc261c}"
MOODLE_ROOT="${MOODLE_ROOT:-/var/www/html/moodle}"
WEB_USER="${WEB_USER:-www-data}"
INSTALL_DIR="$MOODLE_ROOT/local/devtestlab"
LOG_FILE="/var/log/ofppt-devtestlab.log"
APACHE_CONF="/etc/apache2/sites-available/moodle-dtl.conf"

echo ""
echo -e "${BOLD}═══ OFPPT Academy — Déploiement PROD DevTest Labs ═══${NC}"
echo ""

# ── Vérifications prérequis ───────────────────────────────────────────────────
[[ $EUID -eq 0 ]] || err "Ce script doit être exécuté en root (sudo)"
[[ -d "$MOODLE_ROOT" ]] || err "Moodle introuvable dans $MOODLE_ROOT"
command -v php  &>/dev/null || err "PHP non installé"
command -v curl &>/dev/null || err "curl non installé"
command -v openssl &>/dev/null || err "openssl non installé"

PHP_VERSION=$(php -r 'echo PHP_MAJOR_VERSION . "." . PHP_MINOR_VERSION;')
log "PHP $PHP_VERSION | Moodle : $MOODLE_ROOT | Web user : $WEB_USER"

# ── Extension PHP cURL ────────────────────────────────────────────────────────
if ! php -m | grep -q curl; then
    warn "Extension PHP curl manquante — installation..."
    apt-get install -y "php${PHP_VERSION}-curl" 2>/dev/null || \
        err "Installer manuellement : apt-get install php-curl"
fi
log "Extension PHP curl : OK"

# ── Récupérer le client secret (interactif si absent) ────────────────────────
if [[ -z "${AZURE_CLIENT_SECRET:-}" ]]; then
    echo -e "${YELLOW}Le client secret Azure est requis.${NC}"
    echo -e "  SP Name  : sp-ofppt-moodle-dtl"
    echo -e "  Client ID: $AZURE_CLIENT_ID"
    read -r -s -p "AZURE_CLIENT_SECRET : " AZURE_CLIENT_SECRET
    echo ""
fi
[[ -n "$AZURE_CLIENT_SECRET" ]] || err "AZURE_CLIENT_SECRET ne peut pas être vide"

# ── Récupérer MOODLE_WWWROOT ──────────────────────────────────────────────────
if [[ -z "${MOODLE_WWWROOT:-}" ]]; then
    # Essayer de lire depuis la config Moodle
    MOODLE_WWWROOT=$(php -r "
        define('MOODLE_INTERNAL', true);
        require '$MOODLE_ROOT/config.php';
        echo \$CFG->wwwroot;
    " 2>/dev/null) || MOODLE_WWWROOT=""
fi
if [[ -z "$MOODLE_WWWROOT" ]]; then
    read -r -p "MOODLE_WWWROOT (ex: https://moodle.ofppt-academy.ma) : " MOODLE_WWWROOT
fi
[[ -n "$MOODLE_WWWROOT" ]] || err "MOODLE_WWWROOT ne peut pas être vide"
log "MOODLE_WWWROOT : $MOODLE_WWWROOT"

# ── Générer une clé secrète TP forte ─────────────────────────────────────────
TP_SECRET_KEY="ofppt-tp-$(openssl rand -hex 16)"
log "Clé TP générée (24 octets aléatoires)"

# ── Copie des fichiers PHP ────────────────────────────────────────────────────
log "Installation dans $INSTALL_DIR ..."
mkdir -p "$INSTALL_DIR"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for f in config.php azure_dtl_api.php launch_tp.php status.php setup_moodle_activities.php; do
    cp -v "$SCRIPT_DIR/$f" "$INSTALL_DIR/$f"
done

chown -R "$WEB_USER:$WEB_USER" "$INSTALL_DIR"
chmod 750 "$INSTALL_DIR"
chmod 640 "$INSTALL_DIR"/*.php
log "Fichiers PHP déployés dans $INSTALL_DIR"

# ── Fichier de log ────────────────────────────────────────────────────────────
touch "$LOG_FILE"
chown "$WEB_USER:$WEB_USER" "$LOG_FILE"
chmod 640 "$LOG_FILE"

# ── Configuration Apache (fragment inclus dans le VirtualHost Moodle) ─────────
# Ce fichier doit être inclus (Include) dans le <VirtualHost> Moodle existant
SNIPPET_FILE="/etc/apache2/conf-available/ofppt-dtl-env.conf"
cat > "$SNIPPET_FILE" << EOF
# OFPPT DevTest Labs — Variables d'environnement Azure
# Généré le : $(date '+%Y-%m-%d %H:%M:%S')
# ATTENTION : protéger ce fichier (chmod 640)
SetEnv AZURE_TENANT_ID       $AZURE_TENANT_ID
SetEnv AZURE_CLIENT_ID       $AZURE_CLIENT_ID
SetEnv AZURE_CLIENT_SECRET   $AZURE_CLIENT_SECRET
SetEnv AZURE_SUBSCRIPTION_ID $AZURE_SUBSCRIPTION_ID
SetEnv MOODLE_WWWROOT        $MOODLE_WWWROOT
SetEnv TP_SECRET_KEY         $TP_SECRET_KEY
EOF

chmod 640 "$SNIPPET_FILE"
chown root:www-data "$SNIPPET_FILE"

# Activer le snippet Apache
a2enconf ofppt-dtl-env 2>/dev/null || true

log "Configuration Apache écrite dans $SNIPPET_FILE"
warn "Vérifiez que votre VirtualHost Moodle charge bien ce fichier, ou ajoutez :"
echo -e "  ${CYAN}Include /etc/apache2/conf-available/ofppt-dtl-env.conf${NC}"
echo -e "  dans le bloc <VirtualHost> de Moodle dans /etc/apache2/sites-enabled/"

# ── Vérifier la syntaxe Apache ────────────────────────────────────────────────
if apache2ctl configtest 2>/dev/null; then
    log "Syntaxe Apache : OK"
    systemctl reload apache2 && log "Apache rechargé" || warn "Rechargement Apache échoué — faire manuellement"
else
    warn "Syntaxe Apache invalide — vérifiez manuellement avant de recharger"
fi

# ── Vérifier la connectivité Azure (token) ────────────────────────────────────
log "Test de connectivité Azure (token OAuth2)..."
TOKEN_RESP=$(curl -s -X POST \
    "https://login.microsoftonline.com/$AZURE_TENANT_ID/oauth2/v2.0/token" \
    -d "grant_type=client_credentials&client_id=$AZURE_CLIENT_ID&client_secret=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$AZURE_CLIENT_SECRET'))" 2>/dev/null || echo "$AZURE_CLIENT_SECRET")&scope=https://management.azure.com/.default" \
    --max-time 10 2>/dev/null)

if echo "$TOKEN_RESP" | grep -q '"access_token"'; then
    log "Token Azure obtenu avec succès ✅"
else
    warn "Impossible d'obtenir le token Azure — vérifiez le client secret et les credentials"
    echo "  Réponse Azure : $(echo "$TOKEN_RESP" | head -c 200)"
fi

# ── Créer les activités Moodle ────────────────────────────────────────────────
log "Création des activités Moodle 'Lancer le TP'..."
sudo -u "$WEB_USER" php "$INSTALL_DIR/setup_moodle_activities.php" 2>/dev/null || \
    warn "setup_moodle_activities.php : relancer manuellement si les cours n'existent pas encore"

# ── Résumé ────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}══════════════════════════════════════════════════════${NC}"
echo -e "  ${GREEN}✅ Déploiement PROD terminé !${NC}"
echo -e "══════════════════════════════════════════════════════"
echo ""
echo -e "  ${BOLD}Variables configurées :${NC}"
echo -e "  - AZURE_TENANT_ID       : $AZURE_TENANT_ID"
echo -e "  - AZURE_CLIENT_ID       : $AZURE_CLIENT_ID"
echo -e "  - AZURE_SUBSCRIPTION_ID : $AZURE_SUBSCRIPTION_ID"
echo -e "  - MOODLE_WWWROOT        : $MOODLE_WWWROOT"
echo -e "  - AZURE_CLIENT_SECRET   : [défini — voir $SNIPPET_FILE]"
echo ""
echo -e "  ${BOLD}Étapes suivantes :${NC}"
echo -e "  1. Vérifier que $SNIPPET_FILE est inclus dans le VHost Moodle"
echo -e "  2. Recharger Apache : ${CYAN}systemctl reload apache2${NC}"
echo -e "  3. Tester : ${CYAN}$MOODLE_WWWROOT/local/devtestlab/launch_tp.php?tp=CC101-TP1${NC}"
echo ""
echo -e "  ${BOLD}Logs :${NC}"
echo -e "  ${CYAN}tail -f $LOG_FILE${NC}"
echo ""
