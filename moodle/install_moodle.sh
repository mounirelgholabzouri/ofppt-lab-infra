#!/bin/bash
# =============================================================================
# install_moodle.sh — Installation automatique de Moodle pour OFPPT-Lab
# =============================================================================
# Auteur   : Projet OFPPT
# Version  : 1.0
# Usage    : sudo bash install_moodle.sh
# =============================================================================

set -euo pipefail

# ── Couleurs ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; NC='\033[0m'

# ── Variables de configuration ────────────────────────────────────────────────
MOODLE_VERSION="4.3"
MOODLE_DIR="/var/www/html/moodle"
MOODLE_DATA="/var/moodledata"
DB_NAME="moodledb"
DB_USER="moodleuser"
DB_PASS="MoodlePass@2024!"
DB_HOST="localhost"
ADMIN_USER="admin"
ADMIN_PASS="Admin@OFPPT2024!"
ADMIN_EMAIL="admin@ofppt.ma"
SITE_NAME="OFPPT Lab - Plateforme Pédagogique"
SITE_URL="http://localhost/moodle"
PHP_VERSION="8.1"

log()     { echo -e "${GREEN}[INFO]${NC}  $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
section() { echo -e "\n${BLUE}═══ $1 ═══${NC}"; }

# ── Vérification root ─────────────────────────────────────────────────────────
[[ $EUID -ne 0 ]] && error "Ce script doit être exécuté en tant que root (sudo)"

section "Mise à jour du système"
apt-get update -y && apt-get upgrade -y
log "Système mis à jour"

section "Installation de Apache2"
apt-get install -y apache2
systemctl enable apache2
systemctl start apache2
log "Apache2 installé et démarré"

section "Installation de PHP ${PHP_VERSION}"
apt-get install -y software-properties-common
add-apt-repository -y ppa:ondrej/php
apt-get update -y
apt-get install -y \
    php${PHP_VERSION} \
    php${PHP_VERSION}-cli \
    php${PHP_VERSION}-common \
    php${PHP_VERSION}-curl \
    php${PHP_VERSION}-gd \
    php${PHP_VERSION}-intl \
    php${PHP_VERSION}-mbstring \
    php${PHP_VERSION}-mysql \
    php${PHP_VERSION}-soap \
    php${PHP_VERSION}-xml \
    php${PHP_VERSION}-xmlrpc \
    php${PHP_VERSION}-zip \
    php${PHP_VERSION}-opcache \
    libapache2-mod-php${PHP_VERSION}
log "PHP ${PHP_VERSION} installé avec toutes les extensions"

section "Configuration PHP pour Moodle"
PHP_INI="/etc/php/${PHP_VERSION}/apache2/php.ini"
sed -i 's/^upload_max_filesize.*/upload_max_filesize = 512M/'   "$PHP_INI"
sed -i 's/^post_max_size.*/post_max_size = 512M/'               "$PHP_INI"
sed -i 's/^max_execution_time.*/max_execution_time = 360/'      "$PHP_INI"
sed -i 's/^max_input_vars.*/max_input_vars = 5000/'             "$PHP_INI"
sed -i 's/^memory_limit.*/memory_limit = 512M/'                 "$PHP_INI"
log "PHP configuré"

section "Installation de MariaDB"
apt-get install -y mariadb-server mariadb-client
systemctl enable mariadb
systemctl start mariadb

# Sécurisation et création de la base
mysql -u root <<SQL
DELETE FROM mysql.user WHERE User='';
DROP DATABASE IF EXISTS test;
CREATE DATABASE IF NOT EXISTS ${DB_NAME} DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'${DB_HOST}' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'${DB_HOST}';
FLUSH PRIVILEGES;
SQL
log "MariaDB configuré — base '${DB_NAME}' créée"

section "Téléchargement et installation de Moodle ${MOODLE_VERSION}"
apt-get install -y git curl wget unzip
cd /tmp
git clone --depth=1 --branch=MOODLE_$(echo $MOODLE_VERSION | tr '.' '_')_STABLE \
    https://github.com/moodle/moodle.git moodle-src || {
    warn "Clonage git échoué, téléchargement via wget..."
    wget -q "https://packaging.moodle.org/stable$(echo $MOODLE_VERSION | tr -d '.')/moodle-latest-$(echo $MOODLE_VERSION | tr '.' '').tgz" \
        -O moodle.tgz
    tar xzf moodle.tgz
    mv moodle moodle-src
}

cp -r /tmp/moodle-src "$MOODLE_DIR"
mkdir -p "$MOODLE_DATA"
chmod 777 "$MOODLE_DATA"
chown -R www-data:www-data "$MOODLE_DIR" "$MOODLE_DATA"
log "Moodle déployé dans ${MOODLE_DIR}"

section "Configuration Apache VirtualHost"
cat > /etc/apache2/sites-available/moodle.conf <<APACHE
<VirtualHost *:80>
    ServerName localhost
    DocumentRoot /var/www/html
    DirectoryIndex index.php

    <Directory /var/www/html/moodle>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog  \${APACHE_LOG_DIR}/moodle_error.log
    CustomLog \${APACHE_LOG_DIR}/moodle_access.log combined
</VirtualHost>
APACHE

a2ensite moodle.conf
a2enmod rewrite
a2dissite 000-default.conf
systemctl reload apache2
log "VirtualHost Apache configuré"

section "Installation CLI de Moodle"
sudo -u www-data php "${MOODLE_DIR}/admin/cli/install.php" \
    --chmod=2777 \
    --lang=fr \
    --wwwroot="${SITE_URL}" \
    --dataroot="${MOODLE_DATA}" \
    --dbtype=mariadb \
    --dbhost="${DB_HOST}" \
    --dbname="${DB_NAME}" \
    --dbuser="${DB_USER}" \
    --dbpass="${DB_PASS}" \
    --fullname="${SITE_NAME}" \
    --shortname="OFPPT-Lab" \
    --adminuser="${ADMIN_USER}" \
    --adminpass="${ADMIN_PASS}" \
    --adminemail="${ADMIN_EMAIL}" \
    --non-interactive \
    --agree-license
log "Moodle installé via CLI"

section "Configuration du cron Moodle"
(crontab -l 2>/dev/null; echo "*/1 * * * * /usr/bin/php ${MOODLE_DIR}/admin/cli/cron.php > /dev/null 2>&1") | crontab -
log "Cron Moodle configuré (chaque minute)"

section "Installation terminée"
echo ""
log "✅ Moodle ${MOODLE_VERSION} installé avec succès !"
echo -e "   URL       : ${YELLOW}${SITE_URL}${NC}"
echo -e "   Admin     : ${YELLOW}${ADMIN_USER} / ${ADMIN_PASS}${NC}"
echo -e "   Base DB   : ${YELLOW}${DB_NAME} (${DB_USER})${NC}"
echo -e "   Données   : ${YELLOW}${MOODLE_DATA}${NC}"
