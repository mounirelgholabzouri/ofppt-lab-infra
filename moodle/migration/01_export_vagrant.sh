#!/bin/bash
# =============================================================================
# 01_export_vagrant.sh -- Export Moodle depuis Vagrant vm-cloud vers Azure
# =============================================================================
# Executer DANS la VM Vagrant vm-cloud en tant que root :
#
#   vagrant ssh vm-cloud -- "sudo bash /vagrant/moodle/migration/01_export_vagrant.sh"
#
# Produit : /vagrant/moodle-migration.tar.gz (accessible sur l'hote Windows)
# =============================================================================

set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
log()  { echo -e "${GREEN}[EXPORT]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC}   $1"; }
err()  { echo -e "${RED}[ERREUR]${NC} $1"; exit 1; }

MOODLE_ROOT="/var/www/html/moodle"
EXPORT_NAME="moodle-migration-$(date +%Y%m%d-%H%M%S)"
EXPORT_DIR="/tmp/$EXPORT_NAME"
OUTPUT_ARCHIVE="/tmp/moodle-migration.tar.gz"

echo ""
echo -e "${BOLD}=== OFPPT Academy -- Export Moodle (Vagrant -> Azure) ===${NC}"
echo ""

# -- Verifications ------------------------------------------------------------
[[ $EUID -eq 0 ]] || err "Executer en root : sudo bash $0"
[[ -d "$MOODLE_ROOT" ]] || err "Moodle introuvable dans $MOODLE_ROOT"
command -v mysqldump &>/dev/null || err "mysqldump non installe"
command -v php &>/dev/null || err "PHP non installe"

log "Moodle detecte : $MOODLE_ROOT"

# -- Lire la config Moodle ----------------------------------------------------
log "Lecture de la configuration Moodle..."

# Parser config.php avec grep (plus fiable que php eval)
MOODLE_CFG="$MOODLE_ROOT/config.php"
[[ -f "$MOODLE_CFG" ]] || err "config.php introuvable : $MOODLE_CFG"

DB_HOST=$(grep -oP "\\\$CFG->dbhost\s*=\s*'\K[^']+" "$MOODLE_CFG" 2>/dev/null || echo "localhost")
DB_NAME=$(grep -oP "\\\$CFG->dbname\s*=\s*'\K[^']+" "$MOODLE_CFG" 2>/dev/null || echo "moodle")
DB_USER=$(grep -oP "\\\$CFG->dbuser\s*=\s*'\K[^']+" "$MOODLE_CFG" 2>/dev/null || echo "moodleuser")
DB_PASS=$(grep -oP "\\\$CFG->dbpass\s*=\s*'\K[^']+" "$MOODLE_CFG" 2>/dev/null || echo "")
MOODLE_DATA=$(grep -oP "\\\$CFG->dataroot\s*=\s*'\K[^']+" "$MOODLE_CFG" 2>/dev/null || echo "/var/moodledata")
MOODLE_WWWROOT=$(grep -oP "\\\$CFG->wwwroot\s*=\s*'\K[^']+" "$MOODLE_CFG" 2>/dev/null || echo "")
MOODLE_DB_PREFIX=$(grep -oP "\\\$CFG->prefix\s*=\s*'\K[^']+" "$MOODLE_CFG" 2>/dev/null || echo "mdl_")

# Detecter version Moodle
MOODLE_VERSION="unknown"
if [[ -f "$MOODLE_ROOT/version.php" ]]; then
    MOODLE_VERSION=$(grep -oP "\\\$release\s*=\s*'\K[^']+" "$MOODLE_ROOT/version.php" 2>/dev/null || echo "unknown")
fi

log "  DB Host    : $DB_HOST"
log "  DB Name    : $DB_NAME"
log "  DB User    : $DB_USER"
log "  Moodledata : $MOODLE_DATA"
log "  Wwwroot    : $MOODLE_WWWROOT"
log "  Version    : $MOODLE_VERSION"

# -- Creer repertoire export --------------------------------------------------
mkdir -p "$EXPORT_DIR"
log "Repertoire export : $EXPORT_DIR"

# -- Dump MySQL ---------------------------------------------------------------
log "Export base de donnees MySQL ($DB_NAME)..."
mysqldump \
    --host="$DB_HOST" \
    --user="$DB_USER" \
    --password="$DB_PASS" \
    --single-transaction \
    --routines \
    --triggers \
    "$DB_NAME" > "$EXPORT_DIR/moodle_db.sql"

DB_SIZE=$(du -sh "$EXPORT_DIR/moodle_db.sql" | cut -f1)
log "  Dump OK -- taille : $DB_SIZE"

# -- Archive fichiers Moodle --------------------------------------------------
log "Archive des fichiers Moodle ($MOODLE_ROOT)..."
log "  (exclus : /cache/, /localcache/, /temp/ pour reduire la taille)"

tar -czf "$EXPORT_DIR/moodle_files.tar.gz" \
    --exclude="$MOODLE_ROOT/cache" \
    --exclude="$MOODLE_ROOT/localcache" \
    --exclude="$MOODLE_ROOT/temp" \
    -C "$(dirname $MOODLE_ROOT)" \
    "$(basename $MOODLE_ROOT)"

FILES_SIZE=$(du -sh "$EXPORT_DIR/moodle_files.tar.gz" | cut -f1)
log "  Archive OK -- taille : $FILES_SIZE"

# -- Archive moodledata -------------------------------------------------------
if [[ -d "$MOODLE_DATA" ]]; then
    log "Archive moodledata ($MOODLE_DATA)..."
    tar -czf "$EXPORT_DIR/moodle_data.tar.gz" \
        --exclude="$MOODLE_DATA/cache" \
        --exclude="$MOODLE_DATA/temp" \
        --exclude="$MOODLE_DATA/trashdir" \
        -C "$(dirname $MOODLE_DATA)" \
        "$(basename $MOODLE_DATA)"
    DATA_SIZE=$(du -sh "$EXPORT_DIR/moodle_data.tar.gz" | cut -f1)
    log "  Archive OK -- taille : $DATA_SIZE"
else
    warn "moodledata introuvable : $MOODLE_DATA -- creation archive vide"
    touch "$EXPORT_DIR/moodle_data.tar.gz"
    MOODLE_DATA="/var/moodledata"
fi

# -- Fichier info migration ---------------------------------------------------
cat > "$EXPORT_DIR/migration_info.env" << EOF
# =============================================================
# Informations de migration Moodle
# Genere le : $(date '+%Y-%m-%d %H:%M:%S')
# =============================================================
MOODLE_VERSION=$MOODLE_VERSION
MOODLE_ROOT=$MOODLE_ROOT
MOODLE_DATA=$MOODLE_DATA
MOODLE_WWWROOT_SOURCE=$MOODLE_WWWROOT
DB_HOST=$DB_HOST
DB_NAME=$DB_NAME
DB_USER=$DB_USER
DB_PASS=$DB_PASS
DB_PREFIX=$MOODLE_DB_PREFIX
EXPORT_DATE=$(date '+%Y-%m-%d %H:%M:%S')
EOF

log "Fichier info : $EXPORT_DIR/migration_info.env"

# -- Archive finale -----------------------------------------------------------
log "Creation de l'archive finale..."
tar -czf "$OUTPUT_ARCHIVE" \
    -C "/tmp" \
    "$EXPORT_NAME"

ARCHIVE_SIZE=$(du -sh "$OUTPUT_ARCHIVE" | cut -f1)

# Nettoyage
rm -rf "$EXPORT_DIR"

echo ""
echo -e "${BOLD}============================================================${NC}"
echo -e "  ${GREEN}Export termine avec succes !${NC}"
echo -e "============================================================"
echo ""
echo -e "  Archive : ${CYAN}$OUTPUT_ARCHIVE${NC}"
echo -e "  Taille  : $ARCHIVE_SIZE"
echo ""
echo -e "  ${BOLD}Prochaines etapes (sur Windows) :${NC}"
echo ""
echo -e "  1. L'archive est disponible sur l'hote Windows :"
echo -e "     ${CYAN}$(dirname $0 | sed 's|/vagrant|.|')/moodle-migration.tar.gz${NC}"
echo ""
echo -e "  2. Recuperer le FQDN de la VM Azure (dans azure\\moodle\\moodle_vm_info.txt)"
echo ""
echo -e "  3. Transferer l'archive + le script d'install :"
echo -e "     ${CYAN}scp moodle-migration.tar.gz azureofppt@<FQDN>:/home/azureofppt/${NC}"
echo -e "     ${CYAN}scp moodle\\migration\\02_install_moodle_azure.sh azureofppt@<FQDN>:/home/azureofppt/${NC}"
echo ""
echo -e "  4. Lancer l'installation sur Azure VM :"
echo -e "     ${CYAN}ssh azureofppt@<FQDN> 'sudo bash /home/azureofppt/02_install_moodle_azure.sh'${NC}"
echo ""
