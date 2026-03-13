# OFPPT-Lab — Plateforme de Formation Professionnelle

Infrastructure complète pour l'automatisation des laboratoires de formation OFPPT.

## Structure du projet

```
ofppt-lab/
├── moodle/
│   ├── install_moodle.sh                 # Installation Moodle 4.3
│   └── configure_moodle_pedagogique.sh   # Filières, cours, utilisateurs
├── guacamole/
│   └── install_guacamole.sh              # Passerelle HTML5 (RDP/SSH/VNC)
├── bash/
│   ├── tp_manager.sh                     # Gestionnaire de TP interactif
│   ├── provision_cloud.sh                # VM Lab Cloud (Docker, Terraform, az)
│   ├── provision_reseau.sh               # VM Lab Réseau (GNS3, FRR, Wireshark)
│   └── provision_cyber.sh                # VM Lab Cyber (Metasploit, Nmap...)
├── vagrant/
│   └── Vagrantfile                       # 3 VMs multi-filières
├── azure/
│   ├── azure_infrastructure.sh           # Déploiement Azure CLI (bash)
│   └── main.tf                           # Infrastructure as Code (Terraform)
└── README.md
```

## Démarrage rapide

### Option A — VMs locales (Vagrant)
```bash
cd vagrant/
vagrant up              # Démarrer les 3 VMs
vagrant ssh vm-cloud    # Se connecter au Lab Cloud
vagrant ssh vm-reseau   # Se connecter au Lab Réseaux
vagrant ssh vm-cyber    # Se connecter au Lab Cybersécurité
```

### Option B — Cloud Azure (Terraform)
```bash
cd azure/
terraform init
terraform plan
terraform apply
```

### Option C — Azure CLI (bash)
```bash
cd azure/
bash azure_infrastructure.sh deploy
```

## Filières supportées

| Filière | Outils | IP Vagrant |
|---------|--------|-----------|
| Cloud Computing | Docker, Terraform, Azure CLI, AWS CLI, kubectl | 192.168.56.10 |
| Réseaux & Infrastructure | GNS3, Wireshark, FRR, OpenVPN, WireGuard | 192.168.56.20 |
| Cybersécurité | Metasploit, Nmap, SQLmap, Hydra, Volatility | 192.168.56.30 |

## Prérequis

- VirtualBox 7.0+ et Vagrant 2.3+
- Ou : Azure CLI + Terraform 1.5+
- RAM recommandée : 8 Go minimum (16 Go pour 3 VMs simultanées)
