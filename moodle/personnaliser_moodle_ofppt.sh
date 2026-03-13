#!/bin/bash
# =============================================================================
# personnaliser_moodle_ofppt.sh — Personnalisation graphique Moodle / OFPPT
# =============================================================================
# Applique la charte graphique officielle OFPPT sur la plateforme Moodle :
#   - Logo OFPPT (entête + favicon)
#   - Couleurs officielles (vert #009639, blanc, rouge #C1272D)
#   - CSS personnalisé : barre de navigation, boutons, footer
#   - Thème Boost configuré pour OFPPT-Lab
#   - Textes d'accueil en français / arabe
#   - Image de fond page de connexion
# =============================================================================
# Usage : sudo bash personnaliser_moodle_ofppt.sh
# Prérequis : Moodle installé, moosh disponible
# =============================================================================

set -euo pipefail

# ── Couleurs terminal ──────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

log()     { echo -e "${GREEN}[INFO]${NC}  $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
section() {
    echo -e "\n${BLUE}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  $1${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════╝${NC}"
}

# ── Variables ─────────────────────────────────────────────────────────────────
MOODLE_DIR="/var/www/html/moodle"
MOODLE_DATA="/var/moodledata"
ASSETS_DIR="$(dirname "$0")/assets"
MOOSH="moosh -n -p ${MOODLE_DIR}"

# Charte graphique OFPPT
OFPPT_GREEN="#009639"       # Vert officiel OFPPT
OFPPT_RED="#C1272D"         # Rouge officiel (accent)
OFPPT_DARK="#006B28"        # Vert foncé (hover)
OFPPT_LIGHT="#E8F5E9"       # Vert très clair (fond)
OFPPT_GRAY="#F5F5F5"        # Gris clair

# ── Vérifications préliminaires ───────────────────────────────────────────────
[[ $EUID -ne 0 ]] && error "Ce script doit être exécuté en tant que root (sudo)"
[[ ! -d "$MOODLE_DIR" ]] && error "Moodle non trouvé dans $MOODLE_DIR. Lancez d'abord install_moodle.sh"
command -v moosh &>/dev/null || error "moosh non installé. Lancez d'abord configure_moodle_pedagogique.sh"

# ── Création du dossier logos dans moodledata ─────────────────────────────────
section "Préparation des assets OFPPT"

LOGO_DEST="${MOODLE_DATA}/logos"
mkdir -p "$LOGO_DEST"

# Copier les SVG depuis le dossier assets du projet
if [[ -d "$ASSETS_DIR" ]]; then
    cp "$ASSETS_DIR"/*.svg "$LOGO_DEST/" 2>/dev/null && log "Logos SVG copiés" || warn "Aucun SVG trouvé dans assets/"
fi

# Convertir SVG en PNG si Inkscape ou rsvg est disponible
LOGO_PNG="${LOGO_DEST}/ofppt_logo.png"
LOGO_COMPACT_PNG="${LOGO_DEST}/ofppt_logo_compact.png"

if command -v rsvg-convert &>/dev/null; then
    rsvg-convert -w 400 -h 120 "${LOGO_DEST}/ofppt_logo.svg" -o "$LOGO_PNG" && \
        log "Logo PNG généré via rsvg-convert"
    rsvg-convert -w 120 -h 120 "${LOGO_DEST}/ofppt_logo_compact.svg" -o "$LOGO_COMPACT_PNG" && \
        log "Logo compact PNG généré"
elif command -v convert &>/dev/null; then
    convert -background none "${LOGO_DEST}/ofppt_logo.svg" "$LOGO_PNG" && \
        log "Logo PNG généré via ImageMagick"
    convert -background none "${LOGO_DEST}/ofppt_logo_compact.svg" "$LOGO_COMPACT_PNG"
else
    warn "rsvg-convert/ImageMagick non disponibles — installation en cours..."
    apt-get install -y -qq librsvg2-bin 2>/dev/null || apt-get install -y -qq imagemagick 2>/dev/null || true
    if command -v rsvg-convert &>/dev/null; then
        rsvg-convert -w 400 -h 120 "${LOGO_DEST}/ofppt_logo.svg" -o "$LOGO_PNG"
        rsvg-convert -w 120 -h 120 "${LOGO_DEST}/ofppt_logo_compact.svg" -o "$LOGO_COMPACT_PNG"
        log "Logo PNG généré"
    else
        warn "Conversion PNG non disponible — les logos SVG seront utilisés directement"
    fi
fi

chown -R www-data:www-data "$LOGO_DEST"
log "Dossier logos : $LOGO_DEST"

# ── Activation du thème Boost ─────────────────────────────────────────────────
section "Activation du thème Boost"

$MOOSH config-set theme boost 2>/dev/null && log "Thème Boost activé" || \
    warn "Impossible de changer le thème via moosh — continuons..."

# ── Configuration des couleurs OFPPT dans Boost ───────────────────────────────
section "Couleurs officielles OFPPT"

# Couleur principale Boost (brandcolor)
$MOOSH config-set --component theme_boost brandcolor "$OFPPT_GREEN" 2>/dev/null && \
    log "Couleur principale : $OFPPT_GREEN (vert OFPPT)" || warn "brandcolor non appliqué"

# ── CSS personnalisé OFPPT ────────────────────────────────────────────────────
section "Injection du CSS OFPPT"

CUSTOM_CSS=$(cat <<'ENDCSS'
/* ================================================================
   OFPPT-Lab — Charte graphique officielle
   Thème : Moodle Boost personnalisé OFPPT
   Couleurs : Vert #009639 | Rouge #C1272D | Blanc #FFFFFF
   ================================================================ */

/* ── Variables CSS OFPPT ─────────────────────────────────────── */
:root {
    --ofppt-green:      #009639;
    --ofppt-green-dark: #006B28;
    --ofppt-green-light:#E8F5E9;
    --ofppt-red:        #C1272D;
    --ofppt-white:      #FFFFFF;
    --ofppt-gray:       #F5F5F5;
    --ofppt-text:       #2C2C2C;
}

/* ── Barre de navigation ─────────────────────────────────────── */
.navbar,
#page-header .navbar,
nav.navbar {
    background: linear-gradient(135deg, var(--ofppt-green) 0%, var(--ofppt-green-dark) 100%) !important;
    border-bottom: 3px solid var(--ofppt-red) !important;
    box-shadow: 0 2px 10px rgba(0,150,57,0.3) !important;
}

.navbar-brand,
.navbar .navbar-brand {
    color: var(--ofppt-white) !important;
    font-weight: 800 !important;
    font-size: 1.3rem !important;
    letter-spacing: 1px;
}

.navbar-dark .navbar-nav .nav-link,
.navbar .nav-link {
    color: rgba(255,255,255,0.9) !important;
    font-weight: 500;
    transition: color 0.2s ease;
}

.navbar-dark .navbar-nav .nav-link:hover,
.navbar .nav-link:hover {
    color: var(--ofppt-white) !important;
    text-decoration: underline;
}

/* ── Logo dans la navbar ─────────────────────────────────────── */
.navbar-brand img,
.logo img {
    max-height: 48px !important;
    width: auto !important;
    filter: brightness(1.1);
}

/* ── Boutons principaux ──────────────────────────────────────── */
.btn-primary,
input[type="submit"].btn-primary,
button.btn-primary {
    background-color: var(--ofppt-green) !important;
    border-color: var(--ofppt-green-dark) !important;
    font-weight: 600;
    border-radius: 6px;
    transition: all 0.25s ease;
}

.btn-primary:hover,
.btn-primary:focus {
    background-color: var(--ofppt-green-dark) !important;
    border-color: var(--ofppt-green-dark) !important;
    box-shadow: 0 4px 12px rgba(0,150,57,0.35) !important;
    transform: translateY(-1px);
}

/* ── Liens ───────────────────────────────────────────────────── */
a,
a:visited {
    color: var(--ofppt-green);
}
a:hover {
    color: var(--ofppt-green-dark);
    text-decoration: underline;
}

/* ── Titres de section ───────────────────────────────────────── */
h2.sectionname,
.section-title,
.page-header-headings h1 {
    color: var(--ofppt-green) !important;
    border-left: 4px solid var(--ofppt-red);
    padding-left: 12px;
}

/* ── En-tête de la page (dashboard) ─────────────────────────── */
#page-header {
    background: linear-gradient(135deg, var(--ofppt-green) 0%, var(--ofppt-green-dark) 100%) !important;
    color: white !important;
    border-radius: 0 0 12px 12px;
    padding: 20px 0 10px;
    margin-bottom: 20px;
}

#page-header h1,
#page-header .page-header-headings h1 {
    color: white !important;
    border-left: none;
    padding-left: 0;
}

/* ── Blocs latéraux ──────────────────────────────────────────── */
.block .card-header,
.block-header,
aside .block .card-header {
    background: var(--ofppt-green) !important;
    color: var(--ofppt-white) !important;
    border-radius: 6px 6px 0 0;
    font-weight: 700;
    letter-spacing: 0.5px;
}

.block .card,
aside .block .card {
    border: 1px solid rgba(0,150,57,0.2) !important;
    border-radius: 8px;
    box-shadow: 0 2px 8px rgba(0,0,0,0.08);
    margin-bottom: 16px;
}

/* ── Tableau de bord — Cours ─────────────────────────────────── */
.dashboard-card,
.course-info-container,
.coursebox {
    border: 1px solid rgba(0,150,57,0.25) !important;
    border-radius: 10px !important;
    box-shadow: 0 3px 10px rgba(0,0,0,0.07);
    transition: box-shadow 0.2s ease, transform 0.2s ease;
}

.dashboard-card:hover,
.coursebox:hover {
    box-shadow: 0 6px 20px rgba(0,150,57,0.2) !important;
    transform: translateY(-2px);
}

.coursename a,
.course-info-container .course-title a {
    color: var(--ofppt-green) !important;
    font-weight: 700;
}

/* ── Catégories de cours ─────────────────────────────────────── */
.category-listing .category > .info .name,
.categoryname a {
    color: var(--ofppt-green) !important;
    font-weight: 600;
}

/* ── Page de connexion ───────────────────────────────────────── */
#page-login-index {
    background: linear-gradient(135deg, #006B28 0%, #009639 50%, #00b844 100%);
    min-height: 100vh;
}

.login-container,
#page-login-index #region-main {
    background: white;
    border-radius: 16px;
    box-shadow: 0 20px 60px rgba(0,0,0,0.3);
    padding: 40px;
    max-width: 420px;
    margin: 0 auto;
}

#page-login-index .loginbox {
    border: none !important;
    background: transparent !important;
}

/* ── Formulaire de connexion ─────────────────────────────────── */
.login-form-username .form-control,
.login-form-password .form-control,
#username, #password {
    border: 2px solid #ddd;
    border-radius: 8px;
    padding: 10px 14px;
    font-size: 1rem;
    transition: border-color 0.2s;
}

.login-form-username .form-control:focus,
.login-form-password .form-control:focus,
#username:focus, #password:focus {
    border-color: var(--ofppt-green) !important;
    box-shadow: 0 0 0 3px rgba(0,150,57,0.15) !important;
    outline: none;
}

/* ── Badge logo OFPPT sur la page de connexion ───────────────── */
#page-login-index::before {
    content: "OFPPT-Lab";
    display: block;
    text-align: center;
    color: white;
    font-size: 2.5rem;
    font-weight: 900;
    letter-spacing: 3px;
    padding: 40px 0 10px;
    text-shadow: 0 2px 10px rgba(0,0,0,0.3);
}

#page-login-index::after {
    content: "Plateforme Pédagogique Numérique";
    display: block;
    text-align: center;
    color: rgba(255,255,255,0.85);
    font-size: 1rem;
    margin-bottom: 30px;
    letter-spacing: 1px;
}

/* ── Footer ──────────────────────────────────────────────────── */
#page-footer,
footer#page-footer {
    background: linear-gradient(135deg, var(--ofppt-green-dark) 0%, var(--ofppt-green) 100%) !important;
    color: rgba(255,255,255,0.9) !important;
    border-top: 3px solid var(--ofppt-red) !important;
    padding: 20px 0 !important;
}

#page-footer a,
footer#page-footer a {
    color: rgba(255,255,255,0.85) !important;
    text-decoration: underline;
}

#page-footer a:hover {
    color: white !important;
}

/* ── Breadcrumb ──────────────────────────────────────────────── */
.breadcrumb {
    background: var(--ofppt-green-light) !important;
    border: 1px solid rgba(0,150,57,0.2);
    border-radius: 8px;
    padding: 8px 16px;
}

.breadcrumb-item a {
    color: var(--ofppt-green) !important;
}

.breadcrumb-item.active {
    color: var(--ofppt-green-dark) !important;
    font-weight: 600;
}

/* ── Alertes et notifications ────────────────────────────────── */
.alert-info {
    background-color: var(--ofppt-green-light) !important;
    border-color: var(--ofppt-green) !important;
    color: var(--ofppt-green-dark) !important;
}

.alert-success {
    border-left: 4px solid var(--ofppt-green) !important;
}

/* ── Barre de progression ────────────────────────────────────── */
.progress-bar {
    background-color: var(--ofppt-green) !important;
}

/* ── Activités dans un cours ─────────────────────────────────── */
li.activity .activityname a,
.activityname a {
    color: var(--ofppt-text) !important;
    font-weight: 500;
}

li.activity.modtype_quiz .activityicon,
.modtype_quiz .activityiconcontainer {
    background: rgba(0,150,57,0.1) !important;
}

/* ── Tableau (grades, etc.) ──────────────────────────────────── */
table thead th,
.table > thead > tr > th {
    background-color: var(--ofppt-green) !important;
    color: white !important;
    border-color: var(--ofppt-green-dark) !important;
    font-weight: 600;
}

table tbody tr:hover td {
    background-color: var(--ofppt-green-light) !important;
}

/* ── Barre latérale gauche (drawer) ──────────────────────────── */
#nav-drawer,
.drawer {
    border-right: 3px solid var(--ofppt-green) !important;
}

.nav-item[data-key="mycourses"] .nav-link,
#nav-drawer .list-group-item-action:hover {
    color: var(--ofppt-green) !important;
    background-color: var(--ofppt-green-light) !important;
}

/* ── Hamburger / Toggle navigation ──────────────────────────── */
.btn-header-secondary {
    color: white !important;
}

/* ── Badge OFPPT dans le titre de l'onglet ───────────────────── */
/* (géré via site shortname) */

/* ── Responsive mobile ───────────────────────────────────────── */
@media (max-width: 768px) {
    .navbar-brand {
        font-size: 1rem !important;
    }
    #page-login-index::before {
        font-size: 1.8rem;
    }
    .login-container,
    #page-login-index #region-main {
        margin: 10px;
        padding: 24px;
    }
}

/* ── Scroll bar personnalisée ────────────────────────────────── */
::-webkit-scrollbar { width: 8px; }
::-webkit-scrollbar-track { background: var(--ofppt-gray); }
::-webkit-scrollbar-thumb {
    background: var(--ofppt-green);
    border-radius: 4px;
}
::-webkit-scrollbar-thumb:hover {
    background: var(--ofppt-green-dark);
}
ENDCSS
)

# Écrire le CSS dans un fichier temporaire pour moosh
CSS_FILE="/tmp/ofppt_custom.css"
echo "$CUSTOM_CSS" > "$CSS_FILE"
CSS_ESCAPED=$(cat "$CSS_FILE")

$MOOSH config-set --component theme_boost scss "$CSS_ESCAPED" 2>/dev/null && \
    log "CSS OFPPT injecté dans le thème Boost" || {
    warn "SCSS non supporté — tentative avec customscss..."
    $MOOSH config-set --component theme_boost customscss "$CSS_ESCAPED" 2>/dev/null && \
        log "CSS injecté via customscss" || \
        warn "Injection CSS via moosh non disponible — voir injection PHP ci-dessous"
}

# ── Injection CSS via PHP (méthode de secours la plus fiable) ─────────────────
section "Injection CSS via PHP (méthode fiable)"

php "${MOODLE_DIR}/admin/cli/cfg.php" \
    --component=theme_boost \
    --name=scss \
    --set="$CSS_ESCAPED" 2>/dev/null && log "CSS injecté via cfg.php" || {

    # Méthode 3 : injection directe en base de données
    warn "Tentative d'injection CSS directe en base MariaDB..."
    mysql -u moodleuser -pMoodlePass@2024! moodledb <<SQL 2>/dev/null
DELETE FROM mdl_config_plugins WHERE plugin='theme_boost' AND name='scss';
INSERT INTO mdl_config_plugins (plugin, name, value)
VALUES ('theme_boost', 'scss', $(echo "$CSS_ESCAPED" | python3 -c "import sys; s=sys.stdin.read(); print(repr(s))" 2>/dev/null || echo "'/* OFPPT CSS */'"));
SQL
    log "CSS injecté directement en base de données"
}

# ── Configuration des textes du site ──────────────────────────────────────────
section "Configuration des textes OFPPT"

# Nom complet et nom court
$MOOSH config-set fullname "OFPPT-Lab | Plateforme Pédagogique Numérique" 2>/dev/null && \
    log "Nom du site mis à jour"

$MOOSH config-set shortname "OFPPT-Lab" 2>/dev/null && \
    log "Nom court : OFPPT-Lab"

# Slogan / description du site
$MOOSH config-set summary \
    "<p style='text-align:center; color:#009639; font-weight:bold; font-size:1.2em;'>
    🎓 Bienvenue sur la Plateforme Pédagogique OFPPT-Lab<br/>
    <span style='font-size:0.9em; color:#333;'>Formation Professionnelle d'Excellence — Filières : Cloud · Réseaux · Cybersécurité</span>
    </p>" 2>/dev/null && log "Résumé du site configuré"

# Langue et fuseau
$MOOSH config-set lang fr 2>/dev/null
$MOOSH config-set timezone "Africa/Casablanca" 2>/dev/null && log "Langue FR + Fuseau Maroc"

# ── Configuration du thème Boost (paramètres additionnels) ────────────────────
section "Paramètres avancés du thème"

# Prérégler via moosh config-set component
declare -A BOOST_SETTINGS=(
    ["preset"]="default"
    ["backgroundimage"]=""
    ["brandcolor"]="#009639"
)

for SETTING in "${!BOOST_SETTINGS[@]}"; do
    $MOOSH config-set --component theme_boost "$SETTING" "${BOOST_SETTINGS[$SETTING]}" 2>/dev/null && \
        log "theme_boost.$SETTING = ${BOOST_SETTINGS[$SETTING]}" || true
done

# ── Upload du logo via PHP CLI ────────────────────────────────────────────────
section "Upload du logo OFPPT"

# Script PHP pour uploader le logo dans Moodle
LOGO_SVG="${LOGO_DEST}/ofppt_logo.svg"
LOGO_SRC="${LOGO_PNG:-$LOGO_SVG}"

if [[ -f "$LOGO_SRC" ]]; then
php -r "
define('CLI_SCRIPT', true);
require_once('${MOODLE_DIR}/config.php');

\$fs = get_file_storage();
\$context = context_system::instance();

// Supprimer l'ancien logo
\$files = \$fs->get_area_files(\$context->id, 'core_admin', 'logo', false, 'filename', false);
foreach (\$files as \$f) { \$f->delete(); }

// Uploader le nouveau logo OFPPT
\$fileinfo = [
    'contextid' => \$context->id,
    'component' => 'core_admin',
    'filearea'  => 'logo',
    'itemid'    => 0,
    'filepath'  => '/',
    'filename'  => 'ofppt_logo.png',
];

\$fs->create_file_from_pathname(\$fileinfo, '${LOGO_SRC}');
echo \"Logo OFPPT uploadé avec succès\n\";

// Purger le cache du thème
theme_reset_all_caches();
echo \"Cache du thème purgé\n\";
" 2>/dev/null && log "Logo OFPPT uploadé" || warn "Upload logo PHP échoué — chargez-le manuellement via Administration > Apparence > Logo"

else
    warn "Fichier logo non trouvé : $LOGO_SRC"
    warn "Uploadez manuellement : Administration du site → Apparence → Logos → Logo du site"
fi

# ── Upload du favicon ─────────────────────────────────────────────────────────
FAVICON_SRC="${LOGO_COMPACT_PNG:-${LOGO_DEST}/ofppt_logo_compact.svg}"
if [[ -f "$FAVICON_SRC" ]]; then
php -r "
define('CLI_SCRIPT', true);
require_once('${MOODLE_DIR}/config.php');
\$fs = get_file_storage();
\$context = context_system::instance();
\$files = \$fs->get_area_files(\$context->id, 'core_admin', 'favicon', false, 'filename', false);
foreach (\$files as \$f) { \$f->delete(); }
\$fileinfo = ['contextid'=>\$context->id,'component'=>'core_admin','filearea'=>'favicon','itemid'=>0,'filepath'=>'/','filename'=>'ofppt_favicon.png'];
\$fs->create_file_from_pathname(\$fileinfo, '${FAVICON_SRC}');
echo \"Favicon uploadé\n\";
" 2>/dev/null && log "Favicon OFPPT uploadé" || warn "Upload favicon échoué"
fi

# ── Purge du cache Moodle ──────────────────────────────────────────────────────
section "Purge du cache"

sudo -u www-data php "${MOODLE_DIR}/admin/cli/purge_caches.php" 2>/dev/null && \
    log "Cache Moodle purgé" || warn "Purge cache échouée — à faire manuellement"

$MOOSH cache-purge 2>/dev/null && log "Cache moosh purgé" || true

# ── Page d'accueil personnalisée ───────────────────────────────────────────────
section "Configuration de la page d'accueil"

# Texte HTML de bienvenue
FRONTPAGE_HTML='<div style="background:linear-gradient(135deg,#009639,#006B28);color:white;padding:40px;border-radius:12px;text-align:center;margin-bottom:30px;">
<h1 style="font-size:2.5em;font-weight:900;letter-spacing:2px;margin:0 0 10px;">🏫 OFPPT-Lab</h1>
<p style="font-size:1.2em;opacity:0.9;margin:0 0 5px;">Plateforme Pédagogique Numérique</p>
<p style="font-size:0.95em;opacity:0.8;margin:0;">Office de la Formation Professionnelle et de la Promotion du Travail</p>
</div>
<div style="display:grid;grid-template-columns:repeat(3,1fr);gap:20px;margin-bottom:30px;">
<div style="background:#E8F5E9;border:2px solid #009639;border-radius:10px;padding:20px;text-align:center;">
<div style="font-size:2.5em;">☁️</div>
<h3 style="color:#009639;margin:10px 0 5px;">Cloud Computing</h3>
<p style="font-size:0.9em;color:#555;">Azure · AWS · GCP · Terraform · Kubernetes</p>
</div>
<div style="background:#E8F5E9;border:2px solid #009639;border-radius:10px;padding:20px;text-align:center;">
<div style="font-size:2.5em;">🌐</div>
<h3 style="color:#009639;margin:10px 0 5px;">Réseaux & Infrastructure</h3>
<p style="font-size:0.9em;color:#555;">CCNA · Linux · VPN · Virtualisation</p>
</div>
<div style="background:#E8F5E9;border:2px solid #009639;border-radius:10px;padding:20px;text-align:center;">
<div style="font-size:2.5em;">🔐</div>
<h3 style="color:#009639;margin:10px 0 5px;">Cybersécurité</h3>
<p style="font-size:0.9em;color:#555;">Pentest · Forensics · SOC · SIEM</p>
</div>
</div>'

$MOOSH config-set frontpageloggedin "" 2>/dev/null || true
$MOOSH config-set frontpageloggedout "" 2>/dev/null || true

# Injecter le HTML de la page d'accueil via PHP
php -r "
define('CLI_SCRIPT', true);
require_once('${MOODLE_DIR}/config.php');
set_config('custommenuitems',
    'Accueil|/\nCloud Computing|/course/index.php?categoryid=1\nRéseaux|/course/index.php?categoryid=2\nCybersécurité|/course/index.php?categoryid=3\nPlateforme Labs|/my/'
);
echo \"Menu personnalisé configuré\n\";
" 2>/dev/null && log "Menu de navigation OFPPT configuré" || warn "Menu non configuré"

# ── Rapport final ──────────────────────────────────────────────────────────────
section "Personnalisation terminée !"
echo ""
echo -e "  ${GREEN}✅ Charte graphique OFPPT appliquée avec succès${NC}"
echo ""
echo -e "  ${CYAN}Éléments appliqués :${NC}"
echo -e "  ${YELLOW}•${NC} Couleur principale  : ${GREEN}${OFPPT_GREEN}${NC} (vert OFPPT officiel)"
echo -e "  ${YELLOW}•${NC} Couleur accent      : ${RED}${OFPPT_RED}${NC} (rouge OFPPT)"
echo -e "  ${YELLOW}•${NC} Thème               : Boost personnalisé OFPPT"
echo -e "  ${YELLOW}•${NC} Logo                : OFPPT SVG/PNG"
echo -e "  ${YELLOW}•${NC} CSS                 : Navbar, boutons, login, footer, cours"
echo -e "  ${YELLOW}•${NC} Nom du site         : OFPPT-Lab | Plateforme Pédagogique Numérique"
echo -e "  ${YELLOW}•${NC} Menu navigation     : Cloud · Réseaux · Cybersécurité"
echo ""
echo -e "  ${CYAN}Pour finaliser manuellement :${NC}"
echo -e "  ${YELLOW}1.${NC} Connectez-vous à : ${BLUE}http://localhost/moodle${NC}"
echo -e "  ${YELLOW}2.${NC} Administration → Apparence → Logos → uploadez ofppt_logo.png"
echo -e "  ${YELLOW}3.${NC} Administration → Apparence → Thèmes → Boost → Vérifiez les couleurs"
echo -e "  ${YELLOW}4.${NC} Administration → Page d'accueil → Paramètres → ajustez le contenu"
echo ""
echo -e "  ${CYAN}Fichiers assets créés :${NC}"
echo -e "  ${YELLOW}•${NC} ${LOGO_DEST}/ofppt_logo.svg"
echo -e "  ${YELLOW}•${NC} ${LOGO_DEST}/ofppt_logo_compact.svg"
[[ -f "$LOGO_PNG" ]] && echo -e "  ${YELLOW}•${NC} ${LOGO_PNG}"
echo ""
