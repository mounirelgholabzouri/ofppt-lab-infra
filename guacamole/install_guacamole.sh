#!/bin/bash
# =============================================================================
# install_guacamole.sh — Installation Apache Guacamole pour OFPPT-Lab
# =============================================================================
# Apache Guacamole est la passerelle HTML5 permettant aux stagiaires d'accéder
# aux VMs de TP depuis Moodle sans aucun client à installer.
# Protocoles supportés : RDP, SSH, VNC, Telnet
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; NC='\033[0m'

# ── Versions ──────────────────────────────────────────────────────────────────
GUAC_VERSION="1.5.4"
TOMCAT_VERSION="9"
GUAC_HOME="/etc/guacamole"
MYSQL_CONNECTOR_VERSION="8.0.33"

# ── Base de données Guacamole ─────────────────────────────────────────────────
GUAC_DB="guacamole_db"
GUAC_DB_USER="guacamole_user"
GUAC_DB_PASS="Guac@OFPPT2024!"
DB_ROOT_PASS="Root@OFPPT2024!"

log()     { echo -e "${GREEN}[INFO]${NC}  $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
section() { echo -e "\n${BLUE}═══ $1 ═══${NC}"; }

[[ $EUID -ne 0 ]] && error "Ce script doit être exécuté en tant que root"

section "Mise à jour et dépendances système"
apt-get update -y
apt-get install -y \
    build-essential \
    libcairo2-dev \
    libjpeg-turbo8-dev \
    libpng-dev \
    libtool-bin \
    libossp-uuid-dev \
    libavcodec-dev \
    libavformat-dev \
    libavutil-dev \
    libswscale-dev \
    freerdp2-dev \
    libpango1.0-dev \
    libssh2-1-dev \
    libtelnet-dev \
    libvncserver-dev \
    libwebsockets-dev \
    libpulse-dev \
    libssl-dev \
    libvorbis-dev \
    libwebp-dev \
    curl wget git make gcc
log "Dépendances de compilation installées"

section "Installation de Java & Tomcat ${TOMCAT_VERSION}"
apt-get install -y openjdk-11-jdk tomcat${TOMCAT_VERSION}
systemctl enable tomcat${TOMCAT_VERSION}
log "Java 11 et Tomcat ${TOMCAT_VERSION} installés"

section "Téléchargement des sources Guacamole ${GUAC_VERSION}"
cd /tmp
# Serveur Guacamole (guacd)
wget -q --show-progress \
    "https://downloads.apache.org/guacamole/${GUAC_VERSION}/source/guacamole-server-${GUAC_VERSION}.tar.gz" \
    -O guacamole-server.tar.gz || \
wget -q "https://archive.apache.org/dist/guacamole/${GUAC_VERSION}/source/guacamole-server-${GUAC_VERSION}.tar.gz" \
    -O guacamole-server.tar.gz
tar xzf guacamole-server.tar.gz
log "Sources guacamole-server téléchargées"

# Client Guacamole (webapp .war)
wget -q --show-progress \
    "https://downloads.apache.org/guacamole/${GUAC_VERSION}/binary/guacamole-${GUAC_VERSION}.war" \
    -O guacamole.war || \
wget -q "https://archive.apache.org/dist/guacamole/${GUAC_VERSION}/binary/guacamole-${GUAC_VERSION}.war" \
    -O guacamole.war
log "Webapp guacamole.war téléchargée"

section "Compilation et installation de guacd"
cd /tmp/guacamole-server-${GUAC_VERSION}
./configure --with-init-dir=/etc/init.d
make -j$(nproc)
make install
ldconfig
systemctl daemon-reload
systemctl enable guacd
systemctl start guacd
log "guacd compilé et démarré"

section "Déploiement de l'application web"
mkdir -p /etc/guacamole/{extensions,lib}
cp /tmp/guacamole.war /var/lib/tomcat${TOMCAT_VERSION}/webapps/guacamole.war
log "guacamole.war déployé dans Tomcat"

section "Installation MariaDB & configuration base Guacamole"
apt-get install -y mariadb-server

# Extension d'authentification MySQL
wget -q \
    "https://downloads.apache.org/guacamole/${GUAC_VERSION}/binary/guacamole-auth-jdbc-${GUAC_VERSION}.tar.gz" \
    -O /tmp/guac-auth-jdbc.tar.gz
cd /tmp
tar xzf guac-auth-jdbc.tar.gz
cp guacamole-auth-jdbc-${GUAC_VERSION}/mysql/guacamole-auth-jdbc-mysql-${GUAC_VERSION}.jar \
    /etc/guacamole/extensions/
log "Extension JDBC MySQL installée"

# Connecteur MySQL Java
wget -q \
    "https://dev.mysql.com/get/Downloads/Connector-J/mysql-connector-j-${MYSQL_CONNECTOR_VERSION}.tar.gz" \
    -O /tmp/mysql-connector.tar.gz
cd /tmp
tar xzf mysql-connector.tar.gz
cp mysql-connector-j-${MYSQL_CONNECTOR_VERSION}/mysql-connector-j-${MYSQL_CONNECTOR_VERSION}.jar \
    /etc/guacamole/lib/
log "Connecteur MySQL Java installé"

# Création de la base de données
mysql -u root <<SQL
CREATE DATABASE IF NOT EXISTS ${GUAC_DB} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${GUAC_DB_USER}'@'localhost' IDENTIFIED BY '${GUAC_DB_PASS}';
GRANT SELECT, INSERT, UPDATE, DELETE ON ${GUAC_DB}.* TO '${GUAC_DB_USER}'@'localhost';
FLUSH PRIVILEGES;
SQL

# Import du schéma SQL
cat /tmp/guacamole-auth-jdbc-${GUAC_VERSION}/mysql/schema/*.sql | \
    mysql -u root "${GUAC_DB}"
log "Schéma base Guacamole importé"

section "Configuration guacamole.properties"
cat > ${GUAC_HOME}/guacamole.properties <<PROPS
# Serveur guacd
guacd-hostname: localhost
guacd-port:     4822

# Base de données MySQL
mysql-hostname:    localhost
mysql-port:        3306
mysql-database:    ${GUAC_DB}
mysql-username:    ${GUAC_DB_USER}
mysql-password:    ${GUAC_DB_PASS}

# Sécurité
mysql-default-max-connections-per-user: 5
mysql-auto-create-accounts: false
PROPS

# Lien symbolique pour Tomcat
mkdir -p /usr/share/tomcat${TOMCAT_VERSION}/.guacamole
ln -sf ${GUAC_HOME}/guacamole.properties \
       /usr/share/tomcat${TOMCAT_VERSION}/.guacamole/guacamole.properties
export GUACAMOLE_HOME=${GUAC_HOME}
log "guacamole.properties configuré"

section "Configuration des connexions initiales OFPPT"
# Ajout de connexions de démonstration via SQL
mysql -u root "${GUAC_DB}" <<SQL
-- Connexion SSH Lab Cloud
INSERT IGNORE INTO guacamole_connection (connection_name, protocol)
    VALUES ('Lab-Cloud-SSH', 'ssh');

-- Connexion RDP Lab Windows
INSERT IGNORE INTO guacamole_connection (connection_name, protocol)
    VALUES ('Lab-Windows-RDP', 'rdp');

-- Connexion SSH Lab Réseaux
INSERT IGNORE INTO guacamole_connection (connection_name, protocol)
    VALUES ('Lab-Reseau-SSH', 'ssh');

-- Connexion SSH Lab Cyber
INSERT IGNORE INTO guacamole_connection (connection_name, protocol)
    VALUES ('Lab-Cyber-SSH', 'ssh');
SQL
log "Connexions de démonstration ajoutées"

section "Démarrage des services"
systemctl restart guacd
systemctl restart tomcat${TOMCAT_VERSION}
sleep 5

# Vérification
if systemctl is-active --quiet guacd && systemctl is-active --quiet tomcat${TOMCAT_VERSION}; then
    log "✅ guacd et Tomcat démarrés"
else
    warn "Vérifier les journaux : journalctl -u guacd / journalctl -u tomcat${TOMCAT_VERSION}"
fi

section "Installation Guacamole terminée"
echo ""
log "✅ Apache Guacamole ${GUAC_VERSION} installé avec succès !"
echo -e "   URL Guacamole : ${YELLOW}http://$(hostname -I | awk '{print $1}'):8080/guacamole${NC}"
echo -e "   Admin         : ${YELLOW}guacadmin / guacadmin${NC} (à changer !)"
echo -e "   Base de données: ${YELLOW}${GUAC_DB}${NC}"
echo -e ""
echo -e "${RED}⚠  Pensez à changer le mot de passe guacadmin par défaut !${NC}"
