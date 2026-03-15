#!/bin/bash
# Script d'installation ttyd sur la VM - exécuté via az vm run-command invoke
set -e

# Télécharger ttyd
curl -fsSL https://github.com/tsl0922/ttyd/releases/download/1.7.3/ttyd.x86_64 \
  -o /usr/local/bin/ttyd
chmod +x /usr/local/bin/ttyd

# Créer l'utilisateur azureofppt si absent
useradd -m -s /bin/bash azureofppt 2>/dev/null || true
echo 'azureofppt:Ofppt@lab2026!' | chpasswd

# Créer le service systemd
cat > /etc/systemd/system/ttyd.service << 'SYSTEMD'
[Unit]
Description=ttyd Web Terminal
After=network.target

[Service]
ExecStart=/usr/local/bin/ttyd -p 7681 login
Restart=always
User=root

[Install]
WantedBy=multi-user.target
SYSTEMD

# Activer et démarrer
systemctl daemon-reload
systemctl enable ttyd
systemctl start ttyd

# Vérification
sleep 2
systemctl is-active ttyd && echo "ttyd OK - port 7681 actif" || echo "ERREUR: ttyd failed"
ss -tlnp | grep 7681 || echo "WARN: port 7681 non listé"
