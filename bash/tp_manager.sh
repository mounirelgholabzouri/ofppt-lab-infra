#!/bin/bash
# =============================================================================
# tp_manager.sh — Gestionnaire de TP pour OFPPT-Lab
# =============================================================================
# Gère le cycle de vie des environnements de TP :
#   - Création / démarrage / arrêt / réinitialisation des VMs
#   - Attribution des TP aux stagiaires
#   - Monitoring des ressources
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; PURPLE='\033[0;35m'; NC='\033[0m'
BOLD='\033[1m'

# ── Configuration ─────────────────────────────────────────────────────────────
VAGRANT_DIR="/opt/ofppt-lab/vagrant"
LOG_FILE="/var/log/ofppt-tp-manager.log"
TP_DB="/var/lib/ofppt/tp_sessions.json"
MAX_VMS_PER_USER=2
VM_TIMEOUT=120  # minutes

# ── Fonctions utilitaires ─────────────────────────────────────────────────────
log()     { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1" | tee -a "$LOG_FILE"; }
error()   { echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"; }
section() { echo -e "\n${BLUE}${BOLD}╔═══════════════════════════════════════════╗${NC}"; \
            printf "${BLUE}${BOLD}║  %-41s ║${NC}\n" "$1"; \
            echo -e "${BLUE}${BOLD}╚═══════════════════════════════════════════╝${NC}"; }

mkdir -p "$(dirname "$LOG_FILE")" "$(dirname "$TP_DB")"
[[ -f "$TP_DB" ]] || echo '{"sessions":[]}' > "$TP_DB"

# ── Catalogue des TP disponibles ──────────────────────────────────────────────
declare -A TP_CATALOGUE=(
    ["cloud-azure"]="TP Azure : Déploiement VM et réseau virtuel"
    ["cloud-terraform"]="TP Terraform : Infrastructure as Code"
    ["cloud-docker"]="TP Docker : Conteneurisation et orchestration"
    ["reseau-cisco"]="TP Cisco : Configuration routage inter-VLAN"
    ["reseau-firewall"]="TP Pare-feu : Règles iptables et pfSense"
    ["reseau-vpn"]="TP VPN : OpenVPN et WireGuard"
    ["cyber-scan"]="TP Pentest : Nmap, Nikto, reconnaissance"
    ["cyber-exploit"]="TP Exploitation : Metasploit Framework"
    ["cyber-forensics"]="TP Forensics : Analyse de logs et artefacts"
)

# ══════════════════════════════════════════════════════════════════════════════
# MENU PRINCIPAL
# ══════════════════════════════════════════════════════════════════════════════
show_menu() {
    clear
    echo -e "${CYAN}${BOLD}"
    echo "  ╔═══════════════════════════════════════════════════╗"
    echo "  ║          OFPPT-Lab — Gestionnaire de TP           ║"
    echo "  ║       Plateforme de Formation Professionnelle      ║"
    echo "  ╚═══════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo -e "  ${BOLD}1.${NC}  📋  Lister les TP disponibles"
    echo -e "  ${BOLD}2.${NC}  🚀  Démarrer un TP"
    echo -e "  ${BOLD}3.${NC}  🛑  Arrêter un TP"
    echo -e "  ${BOLD}4.${NC}  🔄  Réinitialiser un TP"
    echo -e "  ${BOLD}5.${NC}  📊  Statut des VMs actives"
    echo -e "  ${BOLD}6.${NC}  👥  Gérer les sessions stagiaires"
    echo -e "  ${BOLD}7.${NC}  📈  Monitoring ressources"
    echo -e "  ${BOLD}8.${NC}  🗂️   Sauvegarder l'état d'un TP"
    echo -e "  ${BOLD}9.${NC}  🧹  Nettoyer les sessions expirées"
    echo -e "  ${BOLD}0.${NC}  🚪  Quitter"
    echo ""
    echo -ne "  ${BOLD}Votre choix [0-9] :${NC} "
}

# ══════════════════════════════════════════════════════════════════════════════
# 1. LISTER LES TP
# ══════════════════════════════════════════════════════════════════════════════
list_tp() {
    section "Catalogue des TP disponibles"
    echo ""
    printf "  ${BOLD}%-20s %-10s %s${NC}\n" "ID TP" "FILIÈRE" "DESCRIPTION"
    printf "  %-20s %-10s %s\n" "─────────────────" "────────" "──────────────────────────────"
    for TP_ID in "${!TP_CATALOGUE[@]}"; do
        FILIERE=$(echo "$TP_ID" | cut -d'-' -f1 | tr '[:lower:]' '[:upper:]')
        printf "  ${GREEN}%-20s${NC} ${CYAN}%-10s${NC} %s\n" "$TP_ID" "$FILIERE" "${TP_CATALOGUE[$TP_ID]}"
    done | sort
    echo ""
}

# ══════════════════════════════════════════════════════════════════════════════
# 2. DÉMARRER UN TP
# ══════════════════════════════════════════════════════════════════════════════
start_tp() {
    section "Démarrage d'un TP"
    list_tp
    echo -ne "  Entrez l'ID du TP : "
    read -r TP_ID
    echo -ne "  Nom du stagiaire  : "
    read -r STAGIAIRE

    if [[ -z "${TP_CATALOGUE[$TP_ID]+_}" ]]; then
        error "TP inconnu : $TP_ID"
        return 1
    fi

    local TP_DIR="${VAGRANT_DIR}/${TP_ID}"
    if [[ ! -d "$TP_DIR" ]]; then
        warn "Répertoire TP non trouvé : $TP_DIR"
        echo -ne "  Créer un environnement de base ? [o/N] "
        read -r ANSWER
        [[ "$ANSWER" =~ ^[Oo]$ ]] || return 1
        mkdir -p "$TP_DIR"
        create_default_vagrantfile "$TP_ID" "$TP_DIR"
    fi

    log "Démarrage du TP '$TP_ID' pour $STAGIAIRE..."
    cd "$TP_DIR"
    vagrant up --provision 2>&1 | tee -a "$LOG_FILE"

    # Enregistrer la session
    local SESSION_ID="$(date +%Y%m%d%H%M%S)-${STAGIAIRE}-${TP_ID}"
    local START_TIME="$(date -Iseconds)"
    python3 -c "
import json, sys
db = json.load(open('${TP_DB}'))
db['sessions'].append({
    'id': '${SESSION_ID}',
    'stagiaire': '${STAGIAIRE}',
    'tp_id': '${TP_ID}',
    'start_time': '${START_TIME}',
    'status': 'running',
    'dir': '${TP_DIR}'
})
json.dump(db, open('${TP_DB}', 'w'), indent=2)
"
    log "✅ TP '$TP_ID' démarré — Session ID : $SESSION_ID"
    echo -e "  ${GREEN}Connectez-vous via Guacamole pour accéder au TP${NC}"
}

# ══════════════════════════════════════════════════════════════════════════════
# 3. ARRÊTER UN TP
# ══════════════════════════════════════════════════════════════════════════════
stop_tp() {
    section "Arrêt d'un TP"
    show_active_sessions
    echo -ne "  ID de session à arrêter : "
    read -r SESSION_ID

    local TP_DIR
    TP_DIR=$(python3 -c "
import json
db = json.load(open('${TP_DB}'))
for s in db['sessions']:
    if s['id'] == '${SESSION_ID}':
        print(s['dir'])
        break
" 2>/dev/null)

    if [[ -z "$TP_DIR" || ! -d "$TP_DIR" ]]; then
        error "Session introuvable : $SESSION_ID"
        return 1
    fi

    cd "$TP_DIR"
    vagrant halt
    # Mettre à jour le statut
    python3 -c "
import json
db = json.load(open('${TP_DB}'))
for s in db['sessions']:
    if s['id'] == '${SESSION_ID}':
        s['status'] = 'stopped'
        s['stop_time'] = '$(date -Iseconds)'
json.dump(db, open('${TP_DB}', 'w'), indent=2)
"
    log "✅ TP arrêté — Session : $SESSION_ID"
}

# ══════════════════════════════════════════════════════════════════════════════
# 4. RÉINITIALISER UN TP
# ══════════════════════════════════════════════════════════════════════════════
reset_tp() {
    section "Réinitialisation d'un TP"
    echo -ne "  ID TP à réinitialiser : "
    read -r TP_ID
    local TP_DIR="${VAGRANT_DIR}/${TP_ID}"
    [[ -d "$TP_DIR" ]] || { error "Répertoire TP introuvable : $TP_DIR"; return 1; }
    cd "$TP_DIR"
    echo -e "  ${RED}⚠  Cette action va DÉTRUIRE et recréer la VM.${NC}"
    echo -ne "  Confirmer [oui/NON] : "
    read -r CONFIRM
    [[ "$CONFIRM" == "oui" ]] || { warn "Réinitialisation annulée."; return 0; }
    vagrant destroy -f
    vagrant up --provision
    log "✅ TP '$TP_ID' réinitialisé"
}

# ══════════════════════════════════════════════════════════════════════════════
# 5. STATUT DES VMs
# ══════════════════════════════════════════════════════════════════════════════
show_status() {
    section "Statut des VMs actives"
    echo ""
    # VirtualBox
    if command -v vboxmanage &>/dev/null; then
        echo -e "  ${BOLD}VirtualBox :${NC}"
        vboxmanage list runningvms | while read -r LINE; do
            echo -e "    ${GREEN}●${NC} $LINE"
        done
    fi
    # Vagrant global
    if command -v vagrant &>/dev/null; then
        echo -e "\n  ${BOLD}Vagrant global :${NC}"
        vagrant global-status --prune 2>/dev/null || true
    fi
    echo ""
    show_active_sessions
}

show_active_sessions() {
    echo -e "\n  ${BOLD}Sessions actives :${NC}"
    python3 -c "
import json
db = json.load(open('${TP_DB}'))
active = [s for s in db['sessions'] if s['status'] == 'running']
if not active:
    print('  Aucune session active')
else:
    print(f'  {\"ID\":<30} {\"STAGIAIRE\":<20} {\"TP\":<20} {\"DÉMARRÉ\":<25}')
    print('  ' + '-'*95)
    for s in active:
        print(f'  {s[\"id\"]:<30} {s[\"stagiaire\"]:<20} {s[\"tp_id\"]:<20} {s[\"start_time\"]:<25}')
"
}

# ══════════════════════════════════════════════════════════════════════════════
# 7. MONITORING
# ══════════════════════════════════════════════════════════════════════════════
show_monitoring() {
    section "Monitoring des ressources"
    echo ""
    echo -e "  ${BOLD}CPU :${NC}"
    top -bn1 | grep "Cpu(s)" | awk '{print "    Utilisation : " $2+$4 "%"}'
    echo ""
    echo -e "  ${BOLD}Mémoire :${NC}"
    free -h | awk 'NR==2{printf "    Total: %s | Utilisé: %s | Libre: %s\n", $2, $3, $4}'
    echo ""
    echo -e "  ${BOLD}Disque :${NC}"
    df -h / | awk 'NR==2{printf "    Total: %s | Utilisé: %s (%s) | Dispo: %s\n", $2, $3, $5, $4}'
    echo ""
    echo -e "  ${BOLD}Services OFPPT :${NC}"
    for SERVICE in apache2 mariadb tomcat9 guacd; do
        if systemctl is-active --quiet "$SERVICE" 2>/dev/null; then
            echo -e "    ${GREEN}●${NC} $SERVICE — actif"
        else
            echo -e "    ${RED}●${NC} $SERVICE — inactif"
        fi
    done
}

# ══════════════════════════════════════════════════════════════════════════════
# Vagrantfile par défaut
# ══════════════════════════════════════════════════════════════════════════════
create_default_vagrantfile() {
    local TP_ID="$1"; local TP_DIR="$2"
    cat > "${TP_DIR}/Vagrantfile" <<VAGRANTFILE
Vagrant.configure("2") do |config|
  config.vm.box = "ubuntu/jammy64"
  config.vm.hostname = "${TP_ID}-lab"
  config.vm.network "private_network", type: "dhcp"
  config.vm.provider "virtualbox" do |vb|
    vb.name   = "OFPPT-${TP_ID}"
    vb.memory = 2048
    vb.cpus   = 2
  end
  config.vm.provision "shell", inline: <<-SHELL
    apt-get update -y
    apt-get install -y net-tools curl wget git vim
    echo "==> TP ${TP_ID} prêt !"
  SHELL
end
VAGRANTFILE
    log "Vagrantfile de base créé pour $TP_ID"
}

# ══════════════════════════════════════════════════════════════════════════════
# BOUCLE PRINCIPALE
# ══════════════════════════════════════════════════════════════════════════════
# Exécution en mode non-interactif si argument passé
if [[ $# -gt 0 ]]; then
    case "$1" in
        start)   start_tp   ;;
        stop)    stop_tp    ;;
        reset)   reset_tp   ;;
        status)  show_status ;;
        list)    list_tp    ;;
        monitor) show_monitoring ;;
        *) echo "Usage: $0 {start|stop|reset|status|list|monitor}" ;;
    esac
    exit 0
fi

# Mode interactif
while true; do
    show_menu
    read -r CHOICE
    case "$CHOICE" in
        1) list_tp ;;
        2) start_tp ;;
        3) stop_tp ;;
        4) reset_tp ;;
        5) show_status ;;
        6) show_active_sessions ;;
        7) show_monitoring ;;
        8) section "Sauvegarde"; warn "Fonctionnalité en développement" ;;
        9) section "Nettoyage"
           python3 -c "
import json
from datetime import datetime, timedelta
db = json.load(open('${TP_DB}'))
cutoff = datetime.now() - timedelta(minutes=${VM_TIMEOUT})
for s in db['sessions']:
    start = datetime.fromisoformat(s['start_time'])
    if s['status'] == 'running' and start < cutoff:
        s['status'] = 'expired'
json.dump(db, open('${TP_DB}', 'w'), indent=2)
print('  Sessions expirées marquées')
" ;;
        0) echo -e "  ${GREEN}Au revoir !${NC}"; exit 0 ;;
        *) warn "Option invalide : $CHOICE" ;;
    esac
    echo -ne "\n  Appuyez sur [Entrée] pour continuer..."
    read -r
done
