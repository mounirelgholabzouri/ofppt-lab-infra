#!/bin/bash
# =============================================================================
# 02_install_moodle_azure.sh -- Installation Moodle sur VM Azure + import data
# =============================================================================
# Executer sur la VM Azure apres avoir transfere :
#   - /home/azureofppt/moodle-migration.tar.gz
#
# Usage (depuis Windows via SSH) :
#   ssh azureofppt@<FQDN> 'sudo bash /home/azureofppt/02_install_moodle_azure.sh'
#
# Variables optionnelles :
#   NEW_WWWROOT  -- URL finale (ex: https://moodle.ofppt-academy.ma)
#                  Defaut : http://<IP_PUBLIQUE>/moodle
# =============================================================================

set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
log()     { echo -e "${GREEN}[INSTALL]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}   $1"; }
err()     { echo -e "${RED}[ERREUR]${NC} $1"; exit 1; }
section() { echo -e "\n${BOLD}--- $1 ---${NC}"; }

[[ $EUID -eq 0 ]] || err "Executer en root : sudo bash $0"

ARCHIVE="/home/azureofppt/moodle-migration.tar.gz"
WORK_DIR="/tmp/moodle-migration-work"
MOODLE_ROOT="/var/www/html/moodle"
MOODLE_DATA="/var/moodledata"
WEB_USER="www-data"

echo ""
echo -e "${BOLD}=== OFPPT Academy -- Installation Moodle sur Azure ===${NC}"
echo ""

# -- Verifications ------------------------------------------------------------
[[ -f "$ARCHIVE" ]] || err "Archive introuvable : $ARCHIVE
  Transferer d'abord : scp moodle-migration.tar.gz azureofppt@<FQDN>:/home/azureofppt/"

# -- Detecter IP publique pour wwwroot par defaut -----------------------------
PUBLIC_IP=$(curl -s --max-time 5 ifconfig.me 2>/dev/null || \
            curl -s --max-time 5 api.ipify.org 2>/dev/null || \
            hostname -I | awk '{print $1}')

NEW_WWWROOT="${NEW_WWWROOT:-http://${PUBLIC_IP}/moodle}"
log "wwwroot cible : $NEW_WWWROOT"

# -- Extraction de l'archive --------------------------------------------------
section "Extraction de l'archive de migration"
mkdir -p "$WORK_DIR"
tar -xzf "$ARCHIVE" -C "$WORK_DIR"

# Trouver le sous-dossier extrait
EXTRACTED=$(find "$WORK_DIR" -maxdepth 1 -mindepth 1 -type d | head -1)
[[ -n "$EXTRACTED" ]] || err "Sous-dossier moodle-migration introuvable dans l'archive"
log "Contenu extrait : $EXTRACTED"

# Charger les infos de migration (grep pour eviter les erreurs de parsing)
INFO_FILE="$EXTRACTED/migration_info.env"
[[ -f "$INFO_FILE" ]] || err "migration_info.env introuvable"

get_val() { grep -m1 "^$1=" "$INFO_FILE" | cut -d'=' -f2-; }

MOODLE_VERSION=$(get_val MOODLE_VERSION)
MOODLE_DATA=$(get_val MOODLE_DATA)
DB_NAME=$(get_val DB_NAME)
DB_USER=$(get_val DB_USER)
DB_PASS=$(get_val DB_PASS)
DB_PREFIX=$(get_val DB_PREFIX)
MOODLE_WWWROOT_SOURCE=$(get_val MOODLE_WWWROOT_SOURCE)

log "DB Name   : $DB_NAME"
log "DB User   : $DB_USER"
log "Moodle v  : $MOODLE_VERSION"
log "wwwroot source : $MOODLE_WWWROOT_SOURCE"

# ============================================================================
section "Installation LAMP (Apache2 + PHP 8.1 + MySQL 8.0)"
# ============================================================================
export DEBIAN_FRONTEND=noninteractive
apt-get update -y -qq

# Apache2
log "Installation Apache2..."
apt-get install -y -qq apache2
a2enmod rewrite
systemctl enable apache2

# PHP 8.1 avec extensions Moodle
log "Installation PHP 8.1 + extensions Moodle..."
apt-get install -y -qq \
    php8.1 \
    php8.1-cli \
    php8.1-fpm \
    php8.1-mysql \
    php8.1-xml \
    php8.1-mbstring \
    php8.1-curl \
    php8.1-zip \
    php8.1-gd \
    php8.1-intl \
    php8.1-soap \
    php8.1-xmlrpc \
    php8.1-ldap \
    php8.1-redis \
    libapache2-mod-php8.1

# MySQL Server
log "Installation MySQL Server..."
apt-get install -y -qq mysql-server

# Outils utiles
apt-get install -y -qq curl git unzip cron

PHP_VER=$(php -r 'echo PHP_MAJOR_VERSION . "." . PHP_MINOR_VERSION;')
log "PHP $PHP_VER installe"

# ============================================================================
section "Configuration PHP pour Moodle"
# ============================================================================
PHP_INI="/etc/php/${PHP_VER}/apache2/php.ini"

# Parametres recommandes pour Moodle
sed -i 's/^max_execution_time.*/max_execution_time = 300/'    "$PHP_INI"
sed -i 's/^max_input_time.*/max_input_time = 300/'           "$PHP_INI"
sed -i 's/^memory_limit.*/memory_limit = 256M/'              "$PHP_INI"
sed -i 's/^post_max_size.*/post_max_size = 50M/'             "$PHP_INI"
sed -i 's/^upload_max_filesize.*/upload_max_filesize = 50M/' "$PHP_INI"
sed -i 's/^;date.timezone.*/date.timezone = Africa\/Casablanca/' "$PHP_INI"

log "PHP configure pour Moodle"

# ============================================================================
section "Configuration MySQL"
# ============================================================================
# Demarrer MySQL si necessaire
systemctl start mysql

# Creer DB + user Moodle
log "Creation base de donnees $DB_NAME et utilisateur $DB_USER..."
mysql -e "
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
"
log "Base de donnees OK"

# ============================================================================
section "Import de la base de donnees Moodle"
# ============================================================================
SQL_FILE="$EXTRACTED/moodle_db.sql"
[[ -f "$SQL_FILE" ]] || err "Dump SQL introuvable : $SQL_FILE"

log "Import du dump SQL (peut prendre quelques minutes)..."
mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" < "$SQL_FILE"
log "Import SQL termine"

# ============================================================================
section "Restauration des fichiers Moodle"
# ============================================================================
FILES_ARCHIVE="$EXTRACTED/moodle_files.tar.gz"
[[ -f "$FILES_ARCHIVE" ]] || err "Archive fichiers Moodle introuvable : $FILES_ARCHIVE"

log "Extraction des fichiers Moodle dans /var/www/html/..."
mkdir -p /var/www/html
tar -xzf "$FILES_ARCHIVE" -C /var/www/html/
log "Fichiers Moodle extraits dans $MOODLE_ROOT"

# ============================================================================
section "Restauration de moodledata"
# ============================================================================
DATA_ARCHIVE="$EXTRACTED/moodle_data.tar.gz"
if [[ -f "$DATA_ARCHIVE" ]] && [[ -s "$DATA_ARCHIVE" ]]; then
    log "Extraction moodledata..."
    PARENT_DATA="$(dirname $MOODLE_DATA)"
    mkdir -p "$PARENT_DATA"
    tar -xzf "$DATA_ARCHIVE" -C "$PARENT_DATA"
    log "moodledata extrait dans $MOODLE_DATA"
else
    log "Archive moodledata vide ou absente -- creation du repertoire vide"
    mkdir -p "$MOODLE_DATA"
fi

# ============================================================================
section "Mise a jour de config.php (wwwroot + dataroot)"
# ============================================================================
MOODLE_CFG="$MOODLE_ROOT/config.php"
[[ -f "$MOODLE_CFG" ]] || err "config.php introuvable apres extraction : $MOODLE_CFG"

# Sauvegarder l'original
cp "$MOODLE_CFG" "${MOODLE_CFG}.orig"

# Mettre a jour wwwroot
sed -i "s|\\$CFG->wwwroot\s*=\s*'[^']*'|\$CFG->wwwroot = '$NEW_WWWROOT'|" "$MOODLE_CFG"
# Mettre a jour dataroot
sed -i "s|\\$CFG->dataroot\s*=\s*'[^']*'|\$CFG->dataroot = '$MOODLE_DATA'|" "$MOODLE_CFG"
# Mettre a jour dbhost (toujours localhost sur Azure)
sed -i "s|\\$CFG->dbhost\s*=\s*'[^']*'|\$CFG->dbhost = 'localhost'|" "$MOODLE_CFG"

log "config.php mis a jour :"
log "  wwwroot  -> $NEW_WWWROOT"
log "  dataroot -> $MOODLE_DATA"
log "  dbhost   -> localhost"

# Mettre a jour wwwroot dans la base de donnees (table mdl_config)
log "Mise a jour wwwroot dans la base de donnees..."
mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "
UPDATE \`${DB_PREFIX}config\` SET value='$NEW_WWWROOT' WHERE name='wwwroot';
" 2>/dev/null || warn "Mise a jour DB wwwroot echouee -- a faire manuellement"

# ============================================================================
section "Permissions fichiers"
# ============================================================================
log "Application des permissions (www-data)..."
chown -R "$WEB_USER:$WEB_USER" "$MOODLE_ROOT"
chmod -R 755 "$MOODLE_ROOT"
chown -R "$WEB_USER:$WEB_USER" "$MOODLE_DATA"
chmod -R 700 "$MOODLE_DATA"
log "Permissions OK"

# ============================================================================
section "Configuration Apache VirtualHost Moodle"
# ============================================================================
VHOST_FILE="/etc/apache2/sites-available/moodle.conf"
cat > "$VHOST_FILE" << VHOST
<VirtualHost *:80>
    ServerAdmin admin@ofppt-academy.ma
    DocumentRoot /var/www/html

    <Directory /var/www/html/moodle>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/moodle_error.log
    CustomLog \${APACHE_LOG_DIR}/moodle_access.log combined
</VirtualHost>
VHOST

a2ensite moodle.conf
a2dissite 000-default.conf 2>/dev/null || true
systemctl restart apache2
log "VirtualHost Apache configure"

# ============================================================================
section "Mise a jour Moodle CLI (upgrade)"
# ============================================================================
log "Execution de Moodle CLI upgrade..."
sudo -u "$WEB_USER" php "$MOODLE_ROOT/admin/cli/upgrade.php" --non-interactive 2>/dev/null || \
    warn "Upgrade CLI : verifier manuellement via l'interface web admin"

# Desactiver le mode maintenance si actif
sudo -u "$WEB_USER" php "$MOODLE_ROOT/admin/cli/maintenance.php" --disable 2>/dev/null || true
log "Mode maintenance desactive"

# ============================================================================
section "Purge du cache Moodle"
# ============================================================================
sudo -u "$WEB_USER" php "$MOODLE_ROOT/admin/cli/purge_caches.php" 2>/dev/null || \
    warn "Purge cache : executer manuellement depuis l'interface admin"
log "Caches purges"

# ============================================================================
section "Nettoyage"
# ============================================================================
rm -rf "$WORK_DIR"
log "Repertoire temporaire nettoye"

# ============================================================================
# Resume final
# ============================================================================
echo ""
echo -e "${BOLD}============================================================${NC}"
echo -e "  ${GREEN}Installation Moodle sur Azure terminee !${NC}"
echo -e "============================================================"
echo ""
echo -e "  ${BOLD}Acces Moodle :${NC}"
echo -e "  ${CYAN}$NEW_WWWROOT${NC}"
echo ""
echo -e "  ${BOLD}Credentials DB :${NC}"
echo -e "  DB       : $DB_NAME"
echo -e "  User     : $DB_USER"
echo -e "  Password : $DB_PASS"
echo ""
echo -e "  ${BOLD}Prochaine etape -- Integration DevTest Labs :${NC}"
echo ""
echo -e "  Depuis Windows (repo ofppt-lab) :"
echo -e "  ${CYAN}scp -r moodle/devtestlab_integration/ azureofppt@${PUBLIC_IP}:/home/azureofppt/dtl/${NC}"
echo ""
echo -e "  Sur Azure VM :"
echo -e "  ${CYAN}AZURE_CLIENT_SECRET='<secret>' MOODLE_WWWROOT='$NEW_WWWROOT' \\"
echo -e "    sudo -E bash /home/azureofppt/dtl/deploy_prod.sh${NC}"
echo ""
echo -e "  ${BOLD}NOTE SSL :${NC}"
echo -e "  Pour HTTPS avec Let's Encrypt :"
echo -e "  ${CYAN}apt-get install -y certbot python3-certbot-apache${NC}"
echo -e "  ${CYAN}certbot --apache -d moodle.ofppt-academy.ma${NC}"
echo ""
echo -e "  ${BOLD}NOTE DNS :${NC} configurer moodle.ofppt-academy.ma -> $PUBLIC_IP" -ForegroundColor Yellow
echo ""
