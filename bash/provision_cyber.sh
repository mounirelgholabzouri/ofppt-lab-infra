#!/bin/bash
# =============================================================================
# provision_cyber.sh — Provisionnement VM Lab Cybersécurité
# =============================================================================
# Configure l'environnement pour les TP Cybersécurité :
#   - Outils de reconnaissance : nmap, recon-ng, theHarvester
#   - Outils d'exploitation : Metasploit, sqlmap, Hydra
#   - Outils forensics : Volatility, Autopsy, binwalk
#   - Environnements vulnérables : DVWA, Metasploitable
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; NC='\033[0m'

log()     { echo -e "${GREEN}[CYBER]${NC}  $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}   $1"; }
error()   { echo -e "${RED}[ERROR]${NC}  $1"; }
section() { echo -e "\n${BLUE}━━━ $1 ━━━${NC}"; }

export DEBIAN_FRONTEND=noninteractive

section "Mise à jour du système"
apt-get update -y && apt-get upgrade -y
apt-get install -y \
    curl wget git vim python3 python3-pip python3-venv \
    net-tools nmap build-essential libssl-dev \
    ruby ruby-dev gcc g++ make cmake \
    snapd flatpak
log "Paquets de base installés"

# ════════════════════════════════════════════════════════
section "Outils de reconnaissance"
# ════════════════════════════════════════════════════════
apt-get install -y \
    nmap \
    masscan \
    netdiscover \
    whois \
    dnsutils \
    dnsrecon \
    fierce \
    dnsenum \
    nikto \
    whatweb \
    dirb \
    gobuster \
    wfuzz

pip3 install theHarvester --break-system-packages 2>/dev/null || \
pip3 install theHarvester || true
# recon-ng : installation depuis git car non disponible sur PyPI
if ! command -v recon-ng &>/dev/null; then
    git clone --depth=1 https://github.com/lanmaster53/recon-ng.git /opt/recon-ng 2>/dev/null && \
        pip3 install -r /opt/recon-ng/REQUIREMENTS --break-system-packages 2>/dev/null || true
    ln -sf /opt/recon-ng/recon-ng /usr/local/bin/recon-ng 2>/dev/null || true
fi
log "Outils de reconnaissance installés"

# ════════════════════════════════════════════════════════
section "Installation Metasploit Framework"
# ════════════════════════════════════════════════════════
if ! command -v msfconsole &>/dev/null; then
    curl -sSLO https://raw.githubusercontent.com/rapid7/metasploit-omnibus/master/config/templates/metasploit-framework-wrappers/msfupdate.erb
    bash msfupdate.erb
    rm -f msfupdate.erb
    log "Metasploit Framework installé"
else
    log "Metasploit déjà présent"
fi

# ════════════════════════════════════════════════════════
section "Outils d'exploitation web"
# ════════════════════════════════════════════════════════
apt-get install -y sqlmap
pip3 install sqlmap --break-system-packages 2>/dev/null || true

# Burp Suite Community (en ligne de commande)
wget -q "https://portswigger.net/burp/releases/download?product=community&type=Jar" \
    -O /opt/burpsuite.jar 2>/dev/null || \
    warn "Burp Suite non téléchargé (télécharger manuellement depuis portswigger.net)"

# OWASP ZAP
wget -q "https://github.com/zaproxy/zaproxy/releases/latest/download/ZAP_LINUX.tar.gz" \
    -O /tmp/zap.tar.gz 2>/dev/null && {
    tar xzf /tmp/zap.tar.gz -C /opt/
    ln -sf /opt/ZAP*/zap.sh /usr/local/bin/zap
    log "OWASP ZAP installé"
} || warn "ZAP non téléchargé"
log "Outils web installés : sqlmap, Burp, ZAP"

# ════════════════════════════════════════════════════════
section "Outils de crack de mots de passe"
# ════════════════════════════════════════════════════════
apt-get install -y \
    hydra \
    medusa \
    john \
    hashcat \
    crunch \
    wordlists 2>/dev/null || true

# Wordlists (rockyou)
if [[ ! -f /usr/share/wordlists/rockyou.txt ]]; then
    mkdir -p /usr/share/wordlists
    wget -q "https://github.com/praetorian-inc/Hob0Rules/raw/master/wordlists/rockyou.txt.gz" \
        -O /usr/share/wordlists/rockyou.txt.gz 2>/dev/null && \
        gunzip /usr/share/wordlists/rockyou.txt.gz && \
        log "Wordlist rockyou.txt installée" || warn "rockyou non téléchargé"
fi
log "Outils de crack installés : hydra, john, hashcat"

# ════════════════════════════════════════════════════════
section "Outils forensics et analyse"
# ════════════════════════════════════════════════════════
apt-get install -y \
    binwalk \
    foremost \
    sleuthkit \
    autopsy \
    volatility3 2>/dev/null || \
pip3 install volatility3 --break-system-packages 2>/dev/null || true

apt-get install -y \
    exiftool \
    steghide \
    file \
    xxd \
    hexedit \
    binutils
# stegdetect non disponible sur Ubuntu 22.04 (utiliser steghide)
# strings est fourni par le paquet binutils (ci-dessus)

# Volatility 3
pip3 install volatility3 --break-system-packages 2>/dev/null || \
pip3 install volatility3
log "Outils forensics installés : binwalk, autopsy, volatility3"

# ════════════════════════════════════════════════════════
section "Outils réseau offensifs"
# ════════════════════════════════════════════════════════
apt-get install -y \
    wireshark \
    tshark \
    tcpdump \
    ettercap-text-only \
    arpwatch \
    netcat-openbsd \
    socat \
    responder \
    impacket-scripts 2>/dev/null || true

pip3 install impacket --break-system-packages 2>/dev/null || \
pip3 install impacket
log "Outils réseau offensifs installés"

# ════════════════════════════════════════════════════════
section "Déploiement DVWA (Damn Vulnerable Web Application)"
# ════════════════════════════════════════════════════════
apt-get install -y apache2 php php-mysql mariadb-server

# Cloner DVWA
if [[ ! -d /var/www/html/dvwa ]]; then
    git clone --depth=1 https://github.com/digininja/DVWA.git /var/www/html/dvwa
    cp /var/www/html/dvwa/config/config.inc.php.dist /var/www/html/dvwa/config/config.inc.php
    # Configurer la base de données DVWA
    sed -i "s/'db_password' => 'p\@ssw0rd'/'db_password' => 'dvwa_pass'/" \
        /var/www/html/dvwa/config/config.inc.php
    # Base de données
    mysql -u root <<SQL
CREATE DATABASE IF NOT EXISTS dvwa;
CREATE USER IF NOT EXISTS 'dvwa'@'localhost' IDENTIFIED BY 'dvwa_pass';
GRANT ALL ON dvwa.* TO 'dvwa'@'localhost';
FLUSH PRIVILEGES;
SQL
    chown -R www-data:www-data /var/www/html/dvwa
    systemctl restart apache2
    log "DVWA déployé : http://localhost/dvwa (admin/password)"
fi

# ════════════════════════════════════════════════════════
section "Création de la structure TP Cybersécurité"
# ════════════════════════════════════════════════════════
TP_BASE="/home/vagrant/tp-cyber"
mkdir -p "${TP_BASE}"/{recon,exploitation,web,forensics,crypto,reseau-offensif}

# TP1 — Reconnaissance
cat > "${TP_BASE}/recon/tp1_recon.sh" <<'SCRIPT'
#!/bin/bash
echo "=== TP1 : Reconnaissance réseau ==="
TARGET="${1:-192.168.1.0/24}"
echo "[*] Scan nmap rapide : $TARGET"
nmap -sn "$TARGET" -oN scan_ping.txt
echo "[*] Scan de ports ouverts :"
nmap -sV -sC -O "$TARGET" -oN scan_full.txt
echo "[*] Résultats sauvegardés dans scan_*.txt"
SCRIPT

# TP2 — Exploitation Metasploit
cat > "${TP_BASE}/exploitation/tp2_metasploit.md" <<'MD'
# TP2 : Exploitation avec Metasploit

## Objectif
Utiliser Metasploit Framework pour exploiter une vulnérabilité sur Metasploitable2.

## Étapes
1. Démarrer msfconsole : `msfconsole`
2. Rechercher un exploit : `search vsftpd`
3. Utiliser l'exploit : `use exploit/unix/ftp/vsftpd_234_backdoor`
4. Configurer la cible : `set RHOSTS 192.168.56.102`
5. Lancer l'exploit : `run`

## Modules recommandés
- `exploit/multi/handler` — Listener shell
- `post/multi/recon/local_exploit_suggester` — Élévation de privilèges
MD

# TP3 — Analyse forensics
cat > "${TP_BASE}/forensics/tp3_forensics.sh" <<'SCRIPT'
#!/bin/bash
echo "=== TP3 : Analyse Forensics ==="
IMAGE="${1:-/tmp/memory.dmp}"
[[ -f "$IMAGE" ]] || { echo "Usage: $0 <image_memoire>"; exit 1; }
echo "[*] Informations système :"
python3 -m volatility3 -f "$IMAGE" windows.info 2>/dev/null || \
python3 -m volatility3 -f "$IMAGE" linux.bash
echo "[*] Processus en cours :"
python3 -m volatility3 -f "$IMAGE" windows.pslist 2>/dev/null || \
python3 -m volatility3 -f "$IMAGE" linux.pslist
SCRIPT

chmod -R +x "${TP_BASE}"
chown -R vagrant:vagrant "${TP_BASE}" 2>/dev/null || true
log "Structure TP Cybersécurité créée dans ${TP_BASE}"

# ════════════════════════════════════════════════════════
section "Configuration du profil Bash"
# ════════════════════════════════════════════════════════
cat >> /home/vagrant/.bashrc <<'BASHRC'

# ─── OFPPT Lab — Cybersécurité ───────────────────────────────────────────────
alias scan='nmap -sV -sC'
alias webtest='nikto -h'
alias tp='ls ~/tp-cyber'
export MSF_DATABASE_CONFIG=/etc/metasploit/database.yml
echo "🔐  Bienvenue dans le Lab Cybersécurité OFPPT !"
echo "    ⚠  Usage éthique et légal UNIQUEMENT sur environnements autorisés"
echo "    Outils : nmap, metasploit, sqlmap, hydra, wireshark, volatility"
BASHRC

section "Provisionnement Cybersécurité terminé"
echo ""
log "✅ Environnement Lab Cybersécurité prêt !"
echo -e "   ${YELLOW}Outils installés :${NC} Nmap, Metasploit, SQLmap, Hydra, John, Hashcat, Volatility, Wireshark"
echo -e "   ${YELLOW}DVWA             :${NC} http://localhost/dvwa (admin / password)"
echo -e "   ${YELLOW}Répertoire TP    :${NC} ~/tp-cyber"
echo -e "   ${RED}⚠  Utilisation UNIQUEMENT dans ce laboratoire isolé !${NC}"
