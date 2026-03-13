#!/bin/bash
# =============================================================================
# provision_cloud.sh — Provisionnement VM Lab Cloud Computing
# =============================================================================
# Installe et configure l'environnement pour les TP Cloud :
#   - Azure CLI, AWS CLI, Google Cloud SDK
#   - Terraform, Ansible, Docker, Kubernetes (kubectl/minikube)
#   - Outils de monitoring cloud
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; NC='\033[0m'

log()     { echo -e "${GREEN}[CLOUD]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $1"; }
section() { echo -e "\n${BLUE}━━━ $1 ━━━${NC}"; }

section "Mise à jour du système"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y && apt-get upgrade -y
apt-get install -y \
    apt-transport-https ca-certificates curl gnupg lsb-release \
    git wget vim unzip jq python3 python3-pip python3-venv \
    software-properties-common net-tools
log "Paquets de base installés"

# ════════════════════════════════════════════════════════
section "Installation Docker CE"
# ════════════════════════════════════════════════════════
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
    gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] \
    https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
    tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
systemctl enable docker
systemctl start docker
usermod -aG docker vagrant 2>/dev/null || true
log "Docker CE installé (version : $(docker --version))"

# Docker Compose v2
DOCKER_COMPOSE_VERSION="2.24.0"
curl -SL "https://github.com/docker/compose/releases/download/v${DOCKER_COMPOSE_VERSION}/docker-compose-linux-$(uname -m)" \
    -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
log "Docker Compose v${DOCKER_COMPOSE_VERSION} installé"

# ════════════════════════════════════════════════════════
section "Installation Terraform"
# ════════════════════════════════════════════════════════
TERRAFORM_VERSION="1.7.0"
wget -q "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip" \
    -O /tmp/terraform.zip
unzip -o /tmp/terraform.zip -d /usr/local/bin/
chmod +x /usr/local/bin/terraform
log "Terraform v${TERRAFORM_VERSION} installé"

# Autocomplétion Terraform
terraform -install-autocomplete 2>/dev/null || true

# ════════════════════════════════════════════════════════
section "Installation Azure CLI"
# ════════════════════════════════════════════════════════
curl -sL https://aka.ms/InstallAzureCLIDeb | bash
log "Azure CLI installé (version : $(az version --query '"azure-cli"' -o tsv 2>/dev/null || echo 'voir az version'))"

# ════════════════════════════════════════════════════════
section "Installation AWS CLI v2"
# ════════════════════════════════════════════════════════
curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
unzip -q -o /tmp/awscliv2.zip -d /tmp/
/tmp/aws/install --update
log "AWS CLI v2 installé"

# ════════════════════════════════════════════════════════
section "Installation kubectl & minikube"
# ════════════════════════════════════════════════════════
# kubectl
KUBECTL_VERSION="$(curl -s https://dl.k8s.io/release/stable.txt 2>/dev/null || echo 'v1.29.0')"
curl -sLO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
rm kubectl
log "kubectl ${KUBECTL_VERSION} installé"

# minikube
curl -sLO "https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64"
install minikube-linux-amd64 /usr/local/bin/minikube
rm minikube-linux-amd64
log "minikube installé"

# ════════════════════════════════════════════════════════
section "Installation Ansible"
# ════════════════════════════════════════════════════════
pip3 install --upgrade ansible ansible-lint --break-system-packages 2>/dev/null || \
pip3 install --upgrade ansible ansible-lint
log "Ansible installé (version : $(ansible --version | head -1))"

# ════════════════════════════════════════════════════════
section "Installation Helm (Kubernetes package manager)"
# ════════════════════════════════════════════════════════
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
log "Helm installé (version : $(helm version --short))"

# ════════════════════════════════════════════════════════
section "Outils Python Cloud"
# ════════════════════════════════════════════════════════
pip3 install --upgrade \
    azure-mgmt-compute \
    azure-mgmt-network \
    azure-identity \
    boto3 \
    google-cloud-storage \
    kubernetes \
    --break-system-packages 2>/dev/null || \
pip3 install --upgrade azure-mgmt-compute azure-mgmt-network boto3 kubernetes
log "SDKs Python cloud installés"

# ════════════════════════════════════════════════════════
section "Création de la structure TP Cloud"
# ════════════════════════════════════════════════════════
TP_BASE="/home/vagrant/tp-cloud"
mkdir -p "${TP_BASE}"/{azure,aws,terraform,docker,kubernetes,ansible}

# TP1 — Azure : Créer une VM
cat > "${TP_BASE}/azure/tp1_create_vm.sh" <<'SCRIPT'
#!/bin/bash
# TP1 : Créer une VM Ubuntu sur Azure
az group create --name rg-ofppt-lab --location westeurope
az vm create \
    --resource-group rg-ofppt-lab \
    --name vm-ofppt-tp1 \
    --image Ubuntu2204 \
    --size Standard_B1s \
    --admin-username azureuser \
    --generate-ssh-keys
az vm open-port --resource-group rg-ofppt-lab --name vm-ofppt-tp1 --port 22
echo "VM créée ! IP : $(az vm show -d -g rg-ofppt-lab -n vm-ofppt-tp1 --query publicIps -o tsv)"
SCRIPT

# TP2 — Terraform : Déploiement IaC
cat > "${TP_BASE}/terraform/main.tf" <<'HCL'
terraform {
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 3.0" }
  }
}
provider "azurerm" { features {} }
resource "azurerm_resource_group" "ofppt" {
  name     = "rg-ofppt-terraform"
  location = "West Europe"
}
output "rg_id" { value = azurerm_resource_group.ofppt.id }
HCL

# TP3 — Docker : Déployer Nginx
cat > "${TP_BASE}/docker/tp3_nginx.sh" <<'SCRIPT'
#!/bin/bash
docker run -d --name nginx-tp3 -p 8080:80 nginx:alpine
echo "Nginx accessible : http://localhost:8080"
SCRIPT

chmod -R +x "${TP_BASE}"
chown -R vagrant:vagrant "${TP_BASE}" 2>/dev/null || true
log "Structure TP Cloud créée dans ${TP_BASE}"

# ════════════════════════════════════════════════════════
section "Configuration du profil Bash"
# ════════════════════════════════════════════════════════
cat >> /home/vagrant/.bashrc <<'BASHRC'

# ─── OFPPT Lab — Cloud ───────────────────────────────────────────────────────
export PATH=$PATH:/usr/local/bin
alias k='kubectl'
alias tf='terraform'
alias tp='ls ~/tp-cloud'
echo "☁  Bienvenue dans le Lab Cloud OFPPT !"
echo "   Commandes disponibles : az, aws, terraform, kubectl, docker, ansible"
BASHRC

section "Provisionnement Cloud terminé"
echo ""
log "✅ Environnement Lab Cloud prêt !"
echo -e "   ${YELLOW}Outils installés :${NC} Docker, Terraform, Azure CLI, AWS CLI, kubectl, Ansible, Helm"
echo -e "   ${YELLOW}Répertoire TP    :${NC} ~/tp-cloud"
