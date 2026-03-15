#!/bin/bash
# =============================================================================
# Artefact DevTest Labs — Outils Cybersécurité OFPPT
# =============================================================================
# Installe : Nmap, Masscan, Nikto, Gobuster, Dirb, sqlmap, Hydra, Medusa,
#            John the Ripper, hashcat, Metasploit Framework, Burp Suite,
#            OWASP ZAP, theHarvester, Volatility, Autopsy, binwalk, DVWA
# =============================================================================

set -euo pipefail

INSTALL_DVWA="${1:-true}"
INSTALL_METASPLOIT="${2:-true}"

log() { echo "[CYBER-TOOLS] $1"; }
err() { echo "[ERREUR] $1" >&2; exit 1; }

log "=== Début installation outils Cybersécurité OFPPT ==="
log "DVWA : $INSTALL_DVWA | Metasploit : $INSTALL_METASPLOIT"

export DEBIAN_FRONTEND=noninteractive

# ── Mise à jour ───────────────────────────────────────────────────────────────
apt-get update -qq
apt-get upgrade -y -qq

# ── Dépendances ───────────────────────────────────────────────────────────────
apt-get install -y -qq \
    apt-transport-https ca-certificates curl gnupg wget git \
    software-properties-common build-essential python3 python3-pip \
    libssl-dev libffi-dev python3-dev ruby ruby-dev \
    openjdk-11-jre-headless \
    net-tools ncat socat

# ── Outils de reconnaissance ──────────────────────────────────────────────────
log "Installation des outils de reconnaissance..."
apt-get install -y -qq \
    nmap \
    masscan \
    netdiscover \
    whois \
    dnsutils \
    fierce \
    dnsrecon \
    dnsenum \
    nikto \
    whatweb \
    wfuzz

# Gobuster (Go)
log "Installation de Gobuster..."
if ! command -v gobuster &>/dev/null; then
    GOBUS_VER="3.6.0"
    wget -q "https://github.com/OJ/gobuster/releases/download/v${GOBUS_VER}/gobuster_Linux_x86_64.tar.gz" \
        -O /tmp/gobuster.tar.gz
    tar -xzf /tmp/gobuster.tar.gz -C /usr/local/bin/ gobuster
    chmod +x /usr/local/bin/gobuster
    rm /tmp/gobuster.tar.gz
    log "Gobuster installé : $(gobuster version 2>/dev/null || echo 'OK')"
fi

# Dirb
apt-get install -y -qq dirb

# theHarvester
pip3 install -q theHarvester 2>/dev/null || apt-get install -y -qq theharvester

# recon-ng
pip3 install -q recon-ng 2>/dev/null || true

log "Outils de reconnaissance installés"

# ── Outils d'exploitation Web ────────────────────────────────────────────────
log "Installation des outils d'exploitation Web..."
apt-get install -y -qq sqlmap

# OWASP ZAP (léger — version CLI)
log "Installation d'OWASP ZAP CLI..."
ZAP_VERSION="2.14.0"
if [[ ! -f /opt/zaproxy/zap.sh ]]; then
    wget -q "https://github.com/zaproxy/zaproxy/releases/download/v${ZAP_VERSION}/ZAP_${ZAP_VERSION}_Linux.tar.gz" \
        -O /tmp/zap.tar.gz
    tar -xzf /tmp/zap.tar.gz -C /opt/
    mv "/opt/ZAP_${ZAP_VERSION}" /opt/zaproxy
    ln -sf /opt/zaproxy/zap.sh /usr/local/bin/zap
    rm /tmp/zap.tar.gz
    log "OWASP ZAP installé : $ZAP_VERSION"
fi

log "Outils Web installés"

# ── Outils de cracking de mots de passe ──────────────────────────────────────
log "Installation des outils de cracking..."
apt-get install -y -qq \
    hydra \
    medusa \
    john \
    hashcat \
    crunch \
    cewl \
    wordlists

# Décompresser la wordlist rockyou
if [[ -f /usr/share/wordlists/rockyou.txt.gz ]]; then
    gunzip -k /usr/share/wordlists/rockyou.txt.gz 2>/dev/null || true
    log "Wordlist rockyou.txt décompressée"
fi

log "Outils de cracking installés"

# ── Metasploit Framework ──────────────────────────────────────────────────────
if [[ "$INSTALL_METASPLOIT" == "true" ]]; then
    log "Installation de Metasploit Framework..."
    if ! command -v msfconsole &>/dev/null; then
        curl -fsSL https://raw.githubusercontent.com/rapid7/metasploit-omnibus/master/config/templates/metasploit-framework-wrappers/msfupdate.erb \
            | sed 's/msfupdate/msfinstall/' > /tmp/msfinstall
        chmod +x /tmp/msfinstall
        /tmp/msfinstall
        rm /tmp/msfinstall

        # Initialiser la base de données MSF
        msfdb init 2>/dev/null || true
        log "Metasploit installé : $(msfconsole --version 2>/dev/null | head -1 || echo 'OK')"
    else
        log "Metasploit déjà installé"
    fi
fi

# ── Outils de forensique ─────────────────────────────────────────────────────
log "Installation des outils forensiques..."
apt-get install -y -qq \
    binwalk \
    foremost \
    exiftool \
    steghide \
    hexedit \
    xxd \
    file \
    strings

# Volatility 3 (analyse mémoire)
log "Installation de Volatility 3..."
if ! command -v vol3 &>/dev/null && ! command -v vol &>/dev/null; then
    pip3 install -q volatility3 2>/dev/null || {
        git clone -q https://github.com/volatilityfoundation/volatility3.git /opt/volatility3
        pip3 install -q -r /opt/volatility3/requirements.txt
        ln -sf /opt/volatility3/vol.py /usr/local/bin/vol3
    }
    log "Volatility 3 installé"
fi

# ── DVWA (Damn Vulnerable Web Application) ───────────────────────────────────
if [[ "$INSTALL_DVWA" == "true" ]]; then
    log "Installation de DVWA..."

    # Installer LAMP stack
    apt-get install -y -qq apache2 php php-mysql php-gd php-xml mariadb-server
    systemctl enable --now apache2 mariadb

    # Cloner DVWA
    if [[ ! -d /var/www/html/dvwa ]]; then
        git clone -q https://github.com/digininja/DVWA.git /var/www/html/dvwa
        chown -R www-data:www-data /var/www/html/dvwa
        chmod -R 755 /var/www/html/dvwa
    fi

    # Configurer DVWA
    cp /var/www/html/dvwa/config/config.inc.php.dist \
       /var/www/html/dvwa/config/config.inc.php 2>/dev/null || true

    sed -i "s/\$_DVWA\[ 'db_password' \] = 'p@ssw0rd'/\$_DVWA[ 'db_password' ] = 'dvwa_pass'/" \
        /var/www/html/dvwa/config/config.inc.php 2>/dev/null || true

    # Créer la base de données DVWA
    mysql -e "CREATE DATABASE IF NOT EXISTS dvwa;" 2>/dev/null || true
    mysql -e "CREATE USER IF NOT EXISTS 'dvwa'@'localhost' IDENTIFIED BY 'dvwa_pass';" 2>/dev/null || true
    mysql -e "GRANT ALL PRIVILEGES ON dvwa.* TO 'dvwa'@'localhost';" 2>/dev/null || true
    mysql -e "FLUSH PRIVILEGES;" 2>/dev/null || true

    # PHP config pour DVWA
    sed -i 's/allow_url_include = Off/allow_url_include = On/' /etc/php/*/apache2/php.ini 2>/dev/null || true

    systemctl restart apache2
    log "DVWA installé sur : http://localhost/dvwa"
    log "DVWA Credentials : admin / password (changer après premier login)"
fi

# ── Variables d'environnement ─────────────────────────────────────────────────
cat >> /home/azureofppt/.bashrc << 'BASHRC'

# ── OFPPT Cybersécurité Lab ──────────────────────────────
alias msf='msfconsole'
alias zap='zap -daemon -port 8090'
alias scan='nmap -sV -sC'
alias portscan='nmap -p- --min-rate 5000'

# Wordlists
export WORDLISTS=/usr/share/wordlists
export ROCKYOU=/usr/share/wordlists/rockyou.txt
BASHRC

# ── ttyd — Terminal SSH dans le navigateur (intégration Moodle) ──────────────
log "Installation de ttyd (SSH web pour l'intégration Moodle)..."
TTYD_PORT=7681
if ! command -v ttyd &>/dev/null; then
    TTYD_VERSION=$(curl -fsSL "https://api.github.com/repos/tsl0922/ttyd/releases/latest" \
                  | grep '"tag_name"' | cut -d'"' -f4 || echo "1.7.4")
    curl -fsSLo /usr/local/bin/ttyd \
        "https://github.com/tsl0922/ttyd/releases/download/${TTYD_VERSION}/ttyd.x86_64"
    chmod +x /usr/local/bin/ttyd
fi
cat > /etc/systemd/system/ttyd.service << SVCEOF
[Unit]
Description=OFPPT Lab - Terminal SSH Web (Moodle Integration)
After=network.target
[Service]
Type=simple
User=azureofppt
ExecStart=/usr/local/bin/ttyd --port $TTYD_PORT --interface 0.0.0.0 --writable bash
Restart=always
RestartSec=3
Environment=HOME=/home/azureofppt
WorkingDirectory=/home/azureofppt
[Install]
WantedBy=multi-user.target
SVCEOF
systemctl daemon-reload
systemctl enable --now ttyd
log "ttyd démarré sur le port $TTYD_PORT"

# ── Résumé ───────────────────────────────────────────────────────────────────
log ""
log "=== Installation Cybersécurité terminée ==="
log "Nmap         : $(nmap --version | head -1 2>/dev/null || echo 'OK')"
log "sqlmap       : $(sqlmap --version 2>/dev/null | head -1 || echo 'OK')"
log "Hydra        : $(hydra --version 2>/dev/null | head -1 || echo 'OK')"
log "hashcat      : $(hashcat --version 2>/dev/null || echo 'OK')"
log "John         : $(john --version 2>/dev/null | head -1 || echo 'OK')"
log "binwalk      : $(binwalk --version 2>/dev/null | head -1 || echo 'OK')"
log "Volatility   : $(vol3 -h 2>/dev/null | head -1 || echo 'OK')"
[[ "$INSTALL_METASPLOIT" == "true" ]] && log "Metasploit   : installé" || log "Metasploit   : non installé"
[[ "$INSTALL_DVWA" == "true" ]]       && log "DVWA         : http://localhost/dvwa" || log "DVWA         : non installé"
log "OWASP ZAP    : $(zap -version 2>/dev/null | head -1 || echo 'installé')"
log "=== VM prête pour les TPs Cybersécurité OFPPT ==="
