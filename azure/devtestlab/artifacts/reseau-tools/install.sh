#!/bin/bash
# =============================================================================
# Artefact DevTest Labs — Outils Réseau & Infrastructure OFPPT
# =============================================================================
# Installe : Wireshark, tcpdump, Nmap, iperf3, mtr, FRRouting,
#            OpenVPN, WireGuard, Easy-RSA, Open vSwitch, iptables/nftables
# =============================================================================

set -euo pipefail

INSTALL_GNS3="${1:-false}"

log() { echo "[RESEAU-TOOLS] $1"; }
err() { echo "[ERREUR] $1" >&2; exit 1; }

log "=== Début installation outils Réseau & Infrastructure OFPPT ==="
log "GNS3 : $INSTALL_GNS3"

export DEBIAN_FRONTEND=noninteractive

# ── Mise à jour ───────────────────────────────────────────────────────────────
apt-get update -qq
apt-get upgrade -y -qq

# ── Dépendances de base ───────────────────────────────────────────────────────
apt-get install -y -qq \
    apt-transport-https ca-certificates curl gnupg wget git \
    software-properties-common build-essential python3 python3-pip

# ── Outils d'analyse réseau ───────────────────────────────────────────────────
log "Installation des outils d'analyse réseau..."
apt-get install -y -qq \
    wireshark \
    tcpdump \
    nmap \
    masscan \
    netdiscover \
    iperf3 \
    mtr \
    traceroute \
    net-tools \
    iputils-ping \
    iproute2 \
    curl \
    wget \
    dnsutils \
    whois \
    netcat-openbsd \
    socat \
    hping3 \
    tshark \
    ncat \
    ngrep \
    tcpflow \
    iftop \
    nethogs \
    bmon \
    vnstat

# Autoriser Wireshark sans root
usermod -aG wireshark azureofppt 2>/dev/null || true
dpkg-reconfigure -f noninteractive wireshark-common 2>/dev/null || true

log "Outils d'analyse installés"

# ── FRRouting (OSPF, BGP, RIP, IS-IS) ────────────────────────────────────────
log "Installation de FRRouting (OSPF/BGP/RIP/IS-IS)..."
if ! command -v vtysh &>/dev/null; then
    curl -fsSL https://deb.frrouting.org/frr/keys.gpg \
        | gpg --dearmor -o /usr/share/keyrings/frrouting.gpg
    echo "deb [signed-by=/usr/share/keyrings/frrouting.gpg] https://deb.frrouting.org/frr \
$(lsb_release -s -c) frr-stable" > /etc/apt/sources.list.d/frr.list
    apt-get update -qq
    apt-get install -y -qq frr frr-pythontools

    # Activer les protocoles de routage
    sed -i 's/ospfd=no/ospfd=yes/' /etc/frr/daemons
    sed -i 's/bgpd=no/bgpd=yes/'   /etc/frr/daemons
    sed -i 's/ripd=no/ripd=yes/'   /etc/frr/daemons
    sed -i 's/isisd=no/isisd=yes/' /etc/frr/daemons

    systemctl enable frr
    log "FRRouting installé : $(vtysh --version 2>/dev/null | head -1)"
else
    log "FRRouting déjà installé"
fi

# ── OpenVPN + Easy-RSA ───────────────────────────────────────────────────────
log "Installation d'OpenVPN et Easy-RSA..."
apt-get install -y -qq openvpn easy-rsa
log "OpenVPN installé : $(openvpn --version | head -1)"

# ── WireGuard ────────────────────────────────────────────────────────────────
log "Installation de WireGuard..."
apt-get install -y -qq wireguard wireguard-tools
log "WireGuard installé : $(wg --version 2>/dev/null || echo 'OK')"

# ── Open vSwitch (SDN) ───────────────────────────────────────────────────────
log "Installation d'Open vSwitch..."
apt-get install -y -qq openvswitch-switch openvswitch-common
systemctl enable --now openvswitch-switch
log "Open vSwitch installé : $(ovs-vsctl --version | head -1)"

# ── iptables / nftables ───────────────────────────────────────────────────────
log "Installation d'iptables et nftables..."
apt-get install -y -qq \
    iptables \
    iptables-persistent \
    nftables \
    conntrack \
    ipset

# Activer le forwarding IP
echo "net.ipv4.ip_forward = 1"     >> /etc/sysctl.conf
echo "net.ipv6.conf.all.forwarding = 1" >> /etc/sysctl.conf
sysctl -p &>/dev/null
log "Forwarding IP activé"

# ── VLAN et interfaces réseau ────────────────────────────────────────────────
log "Installation des outils VLAN..."
apt-get install -y -qq vlan bridge-utils
modprobe 8021q 2>/dev/null || true
echo "8021q" >> /etc/modules

# ── Outils DHCP/DNS ──────────────────────────────────────────────────────────
log "Installation des outils DHCP/DNS..."
apt-get install -y -qq \
    isc-dhcp-server \
    bind9 \
    bind9utils \
    bind9-doc \
    dnsmasq \
    avahi-daemon

# ── SSH avancé ───────────────────────────────────────────────────────────────
apt-get install -y -qq openssh-server sshpass

# ── GNS3 (optionnel) ─────────────────────────────────────────────────────────
if [[ "$INSTALL_GNS3" == "true" ]]; then
    log "Installation de GNS3..."
    add-apt-repository -y ppa:gns3/ppa
    apt-get update -qq
    apt-get install -y -qq gns3-server gns3-gui dynamips vpcs ubridge
    usermod -aG ubridge,libvirt,kvm,wireshark,docker azureofppt 2>/dev/null || true
    log "GNS3 installé"
fi

# ── Activer net.ipv4 pour les VLANs imbriqués ────────────────────────────────
cat >> /etc/sysctl.conf << 'SYSCTL'
# OFPPT Lab — Paramètres réseau avancés
net.ipv4.conf.all.proxy_arp = 1
net.ipv4.conf.all.rp_filter = 0
net.ipv4.conf.default.rp_filter = 0
SYSCTL
sysctl -p &>/dev/null

# ── Alias utiles ──────────────────────────────────────────────────────────────
cat >> /home/azureofppt/.bashrc << 'BASHRC'

# ── OFPPT Réseau & Infrastructure Lab ──────────────────────────────
alias ipt='iptables -L -n -v --line-numbers'
alias nft='nft list ruleset'
alias ovs='ovs-vsctl show'
alias routes='ip route show'
alias ifaces='ip addr show'
alias lports='ss -tulnp'

# FRR VTY shell
alias vtysh='sudo vtysh'
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
log "=== Installation Réseau & Infrastructure terminée ==="
log "Wireshark    : $(tshark --version | head -1 2>/dev/null || echo 'OK')"
log "Nmap         : $(nmap --version | head -1 2>/dev/null || echo 'OK')"
log "FRRouting    : $(vtysh --version 2>/dev/null | head -1 || echo 'OK')"
log "OpenVPN      : $(openvpn --version | head -1 2>/dev/null || echo 'OK')"
log "WireGuard    : $(wg --version 2>/dev/null || echo 'OK')"
log "Open vSwitch : $(ovs-vsctl --version | head -1 2>/dev/null || echo 'OK')"
log "iperf3       : $(iperf3 --version 2>/dev/null | head -1 || echo 'OK')"
[[ "$INSTALL_GNS3" == "true" ]] && log "GNS3         : installé" || log "GNS3         : non installé (paramètre installGns3=false)"
log "=== VM prête pour les TPs Réseau OFPPT ==="
