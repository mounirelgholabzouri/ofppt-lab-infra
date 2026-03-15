#!/bin/bash
# =============================================================================
# Artifact DevTest Labs — Installation ttyd (OFPPT Academy)
# =============================================================================
# Installe ttyd (terminal SSH web, port 7681) + service systemd
# Utilise par les 3 formules : Cloud Computing, Reseau, Cybersecurite
# =============================================================================

set -euo pipefail

TTYD_PORT="${1:-7681}"
TTYD_USER="${2:-azureofppt}"

log() { echo "[TTYD-INSTALL] $1"; }
err() { echo "[ERREUR] $1" >&2; exit 1; }

log "=== Installation ttyd pour OFPPT Academy ==="
log "Port : $TTYD_PORT | Utilisateur : $TTYD_USER"

# --- Verifier si ttyd est deja installe et actif ---
if systemctl is-active --quiet ttyd 2>/dev/null; then
    log "ttyd deja actif sur le port $TTYD_PORT — rien a faire."
    exit 0
fi

# --- Dependances ---
apt-get update -qq
apt-get install -y -qq curl wget 2>/dev/null || true

# --- Telecharger ttyd depuis GitHub releases ---
log "Telechargement de ttyd..."
TTYD_VERSION=$(curl -fsSL "https://api.github.com/repos/tsl0922/ttyd/releases/latest" \
               | grep '"tag_name"' | cut -d'"' -f4 2>/dev/null || echo "1.7.4")

# Fallback si l'API GitHub est limitee
if [ -z "$TTYD_VERSION" ] || [ "$TTYD_VERSION" = "null" ]; then
    TTYD_VERSION="1.7.4"
fi

log "Version : $TTYD_VERSION"

TTYD_URL="https://github.com/tsl0922/ttyd/releases/download/${TTYD_VERSION}/ttyd.x86_64"

if ! curl -fsSLo /usr/local/bin/ttyd "$TTYD_URL"; then
    log "Tentative de telechargement version 1.7.3 (fallback)..."
    curl -fsSLo /usr/local/bin/ttyd \
        "https://github.com/tsl0922/ttyd/releases/download/1.7.3/ttyd.x86_64" || \
        err "Echec telechargement ttyd"
fi

chmod +x /usr/local/bin/ttyd
log "ttyd installe : $(/usr/local/bin/ttyd --version 2>/dev/null || echo 'OK')"

# --- Service systemd ---
log "Creation du service systemd ttyd..."
cat > /etc/systemd/system/ttyd.service << SVCEOF
[Unit]
Description=OFPPT Lab - Terminal SSH Web (Moodle Integration)
After=network.target

[Service]
Type=simple
User=${TTYD_USER}
ExecStart=/usr/local/bin/ttyd --port ${TTYD_PORT} --interface 0.0.0.0 --writable bash
Restart=always
RestartSec=3
Environment=HOME=/home/${TTYD_USER}
WorkingDirectory=/home/${TTYD_USER}

[Install]
WantedBy=multi-user.target
SVCEOF

systemctl daemon-reload
systemctl enable ttyd
systemctl start ttyd

# --- Verification ---
sleep 2
if systemctl is-active --quiet ttyd; then
    log "ttyd demarre avec succes sur le port $TTYD_PORT"
else
    log "AVERTISSEMENT: ttyd non actif, tentative de relance..."
    systemctl restart ttyd
    sleep 3
    systemctl is-active --quiet ttyd && log "ttyd OK apres relance" || err "ttyd echec demarrage"
fi

log "=== ttyd installe et actif — URL: http://<IP>:${TTYD_PORT} ==="
