#!/bin/bash
# =============================================================================
# provision_reseau.sh — Provisionnement VM Lab Réseaux & Infrastructure
# =============================================================================
# Configure l'environnement pour les TP réseau :
#   - Outils d'analyse réseau : Wireshark, tcpdump, nmap, iperf3
#   - Émulateurs réseau : GNS3, EVE-NG client
#   - Configuration réseau avancée : VLANs, routage, VPN
#   - Cisco IOS via images GNS3
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; NC='\033[0m'

log()     { echo -e "${GREEN}[RESEAU]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $1"; }
section() { echo -e "\n${BLUE}━━━ $1 ━━━${NC}"; }

export DEBIAN_FRONTEND=noninteractive

section "Mise à jour du système"
apt-get update -y && apt-get upgrade -y
log "Système mis à jour"

# ════════════════════════════════════════════════════════
section "Outils d'analyse réseau"
# ════════════════════════════════════════════════════════
apt-get install -y \
    wireshark \
    tshark \
    tcpdump \
    nmap \
    netdiscover \
    iperf3 \
    mtr \
    traceroute \
    whois \
    dnsutils \
    net-tools \
    iproute2 \
    iputils-ping \
    iputils-tracepath \
    arping \
    hping3 \
    ettercap-text-only \
    netcat-openbsd \
    socat \
    curl wget git vim jq python3 python3-pip

# Permettre à vagrant d'utiliser wireshark sans root
echo "wireshark-common wireshark-common/install-setuid boolean true" | debconf-set-selections
dpkg-reconfigure -p high wireshark-common
usermod -aG wireshark vagrant 2>/dev/null || true
log "Outils réseau installés (wireshark, nmap, tcpdump...)"

# ════════════════════════════════════════════════════════
section "Configuration réseau avancée"
# ════════════════════════════════════════════════════════
# Activer le forwarding IP
echo "net.ipv4.ip_forward = 1"    >> /etc/sysctl.conf
echo "net.ipv6.conf.all.forwarding = 1" >> /etc/sysctl.conf
sysctl -p
log "IP forwarding activé"

# ════════════════════════════════════════════════════════
section "Installation d'Open vSwitch (OVS)"
# ════════════════════════════════════════════════════════
apt-get install -y openvswitch-switch openvswitch-common
systemctl enable ovs-vswitchd
systemctl start ovs-vswitchd
log "Open vSwitch installé"

# ════════════════════════════════════════════════════════
section "Installation FRRouting (Routage dynamique)"
# ════════════════════════════════════════════════════════
# FRR supporte OSPF, BGP, RIP, IS-IS, etc.
curl -s https://deb.frrouting.org/frr/keys.gpg | \
    gpg --dearmor -o /usr/share/keyrings/frr-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/frr-keyring.gpg] https://deb.frrouting.org/frr $(lsb_release -cs) frr-stable" \
    | tee /etc/apt/sources.list.d/frr.list
apt-get update -y
apt-get install -y frr frr-pythontools
log "FRRouting (OSPF/BGP/RIP) installé"

# ════════════════════════════════════════════════════════
section "Installation OpenVPN & WireGuard"
# ════════════════════════════════════════════════════════
apt-get install -y openvpn easy-rsa
apt-get install -y wireguard wireguard-tools
log "OpenVPN et WireGuard installés"

# ════════════════════════════════════════════════════════
section "Installation iptables & nftables"
# ════════════════════════════════════════════════════════
apt-get install -y iptables iptables-persistent nftables
log "iptables et nftables installés"

# ════════════════════════════════════════════════════════
section "Installation GNS3 Server"
# ════════════════════════════════════════════════════════
apt-get install -y python3-pip python3-venv
add-apt-repository -y ppa:gns3/ppa 2>/dev/null || true
apt-get update -y
apt-get install -y gns3-server 2>/dev/null || {
    warn "GNS3 PPA non disponible, installation via pip..."
    pip3 install gns3-server --break-system-packages 2>/dev/null || \
    pip3 install gns3-server
}
log "GNS3 Server installé"

# ════════════════════════════════════════════════════════
section "Création de la structure TP Réseau"
# ════════════════════════════════════════════════════════
TP_BASE="/home/vagrant/tp-reseau"
mkdir -p "${TP_BASE}"/{vlan,routage,vpn,firewall,analyse,gns3}

# TP1 — VLAN avec OVS
cat > "${TP_BASE}/vlan/tp1_configure_vlans.sh" <<'SCRIPT'
#!/bin/bash
echo "=== TP1 : Configuration VLANs avec Open vSwitch ==="

# Créer un bridge OVS
ovs-vsctl add-br br-ofppt

# Créer des ports trunk et access
ovs-vsctl add-port br-ofppt eth1 trunk=10,20,30
ovs-vsctl add-port br-ofppt vlan10 tag=10 -- set interface vlan10 type=internal
ovs-vsctl add-port br-ofppt vlan20 tag=20 -- set interface vlan20 type=internal
ovs-vsctl add-port br-ofppt vlan30 tag=30 -- set interface vlan30 type=internal

# Configurer les IPs
ip addr add 192.168.10.1/24 dev vlan10
ip addr add 192.168.20.1/24 dev vlan20
ip addr add 192.168.30.1/24 dev vlan30
ip link set vlan10 up
ip link set vlan20 up
ip link set vlan30 up

echo "VLANs configurés :"
ovs-vsctl show
SCRIPT

# TP2 — Routage OSPF avec FRR
cat > "${TP_BASE}/routage/tp2_ospf.sh" <<'SCRIPT'
#!/bin/bash
echo "=== TP2 : Routage dynamique OSPF avec FRRouting ==="

# Activer OSPF dans FRR
sed -i 's/ospfd=no/ospfd=yes/' /etc/frr/daemons
systemctl restart frr

# Configuration OSPF basique
vtysh -c "
configure terminal
router ospf
 router-id 1.1.1.1
 network 192.168.0.0/16 area 0
 passive-interface default
 no passive-interface eth1
exit
write memory
"
echo "OSPF configuré. Vérifier avec : vtysh -c 'show ip ospf neighbor'"
SCRIPT

# TP3 — WireGuard VPN
cat > "${TP_BASE}/vpn/tp3_wireguard.sh" <<'SCRIPT'
#!/bin/bash
echo "=== TP3 : Configuration VPN WireGuard ==="

# Générer les clés
wg genkey | tee /etc/wireguard/private.key | wg pubkey > /etc/wireguard/public.key
chmod 600 /etc/wireguard/private.key

PRIVATE_KEY=$(cat /etc/wireguard/private.key)

# Créer la config WireGuard
cat > /etc/wireguard/wg0.conf <<WG
[Interface]
PrivateKey = ${PRIVATE_KEY}
Address    = 10.0.0.1/24
ListenPort = 51820

# Ajouter un peer (client) :
# [Peer]
# PublicKey  = <CLE_PUBLIQUE_CLIENT>
# AllowedIPs = 10.0.0.2/32
WG

wg-quick up wg0
echo "WireGuard démarré. Interface wg0 créée."
echo "Clé publique du serveur : $(cat /etc/wireguard/public.key)"
SCRIPT

# TP4 — Firewall iptables
cat > "${TP_BASE}/firewall/tp4_iptables.sh" <<'SCRIPT'
#!/bin/bash
echo "=== TP4 : Règles Firewall iptables ==="

# Flush des règles existantes
iptables -F && iptables -X && iptables -Z

# Politique par défaut
iptables -P INPUT   DROP
iptables -P FORWARD DROP
iptables -P OUTPUT  ACCEPT

# Autoriser loopback
iptables -A INPUT -i lo -j ACCEPT

# Autoriser connexions établies
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Autoriser SSH
iptables -A INPUT -p tcp --dport 22 -j ACCEPT

# Autoriser HTTP/HTTPS
iptables -A INPUT -p tcp --dport 80  -j ACCEPT
iptables -A INPUT -p tcp --dport 443 -j ACCEPT

# Autoriser ICMP
iptables -A INPUT -p icmp -j ACCEPT

# NAT pour partage Internet
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
iptables -A FORWARD -i eth1 -o eth0 -j ACCEPT
iptables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT

echo "Règles iptables appliquées."
iptables -L -n -v
SCRIPT

chmod -R +x "${TP_BASE}"
chown -R vagrant:vagrant "${TP_BASE}" 2>/dev/null || true
log "Structure TP Réseau créée dans ${TP_BASE}"

# ════════════════════════════════════════════════════════
section "Configuration du profil Bash"
# ════════════════════════════════════════════════════════
cat >> /home/vagrant/.bashrc <<'BASHRC'

# ─── OFPPT Lab — Réseau ──────────────────────────────────────────────────────
alias ip='ip -c'
alias routes='ip route show'
alias ports='ss -tulnp'
alias interfaces='ip -br addr'
alias tp='ls ~/tp-reseau'
echo "🌐  Bienvenue dans le Lab Réseaux OFPPT !"
echo "    Outils : wireshark, nmap, tcpdump, iperf3, frr, ovs, openvpn, wireguard"
BASHRC

section "Provisionnement Réseau terminé"
echo ""
log "✅ Environnement Lab Réseaux prêt !"
echo -e "   ${YELLOW}Outils installés :${NC} Wireshark, Nmap, FRR, OVS, OpenVPN, WireGuard, iptables, GNS3"
echo -e "   ${YELLOW}Répertoire TP    :${NC} ~/tp-reseau"
