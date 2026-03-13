#!/bin/bash
# =============================================================================
# Artefact DevTest Labs — Outils Cloud Computing OFPPT
# =============================================================================
# Appelé par Azure DevTest Labs lors de la création de la VM.
# Installe : Docker CE, Terraform, kubectl, minikube, Azure CLI, AWS CLI, Ansible
# =============================================================================

set -euo pipefail

DOCKER_COMPOSE_VERSION="${1:-2.24.0}"
TERRAFORM_VERSION="${2:-1.7.0}"

log()  { echo "[CLOUD-TOOLS] $1"; }
err()  { echo "[ERREUR] $1" >&2; exit 1; }

log "=== Début installation outils Cloud Computing OFPPT ==="
log "Docker Compose : $DOCKER_COMPOSE_VERSION | Terraform : $TERRAFORM_VERSION"

export DEBIAN_FRONTEND=noninteractive

# ── Mise à jour du système ────────────────────────────────────────────────────
log "Mise à jour des paquets..."
apt-get update -qq
apt-get upgrade -y -qq

# ── Dépendances communes ──────────────────────────────────────────────────────
apt-get install -y -qq \
    apt-transport-https ca-certificates curl gnupg lsb-release \
    software-properties-common unzip wget git jq \
    python3 python3-pip python3-venv build-essential

# ── Docker CE ────────────────────────────────────────────────────────────────
log "Installation de Docker CE..."
if ! command -v docker &>/dev/null; then
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
        | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
        > /etc/apt/sources.list.d/docker.list

    apt-get update -qq
    apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    systemctl enable --now docker
    log "Docker CE installé : $(docker --version)"
else
    log "Docker déjà installé : $(docker --version)"
fi

# Docker Compose standalone (v2)
if [[ ! -f /usr/local/bin/docker-compose ]]; then
    curl -fsSL "https://github.com/docker/compose/releases/download/v${DOCKER_COMPOSE_VERSION}/docker-compose-linux-x86_64" \
        -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    log "Docker Compose installé : $(docker-compose --version)"
fi

# Ajouter l'utilisateur azureofppt au groupe docker
usermod -aG docker azureofppt 2>/dev/null || true

# ── Terraform ────────────────────────────────────────────────────────────────
log "Installation de Terraform $TERRAFORM_VERSION..."
if ! command -v terraform &>/dev/null; then
    wget -q "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip" \
        -O /tmp/terraform.zip
    unzip -q /tmp/terraform.zip -d /usr/local/bin/
    rm /tmp/terraform.zip
    log "Terraform installé : $(terraform version | head -1)"
else
    log "Terraform déjà installé : $(terraform version | head -1)"
fi

# ── Azure CLI ────────────────────────────────────────────────────────────────
log "Installation d'Azure CLI..."
if ! command -v az &>/dev/null; then
    curl -sL https://aka.ms/InstallAzureCLIDeb | bash
    log "Azure CLI installé : $(az version --query '\"azure-cli\"' -o tsv)"
else
    log "Azure CLI déjà installé : $(az version --query '\"azure-cli\"' -o tsv)"
fi

# ── AWS CLI v2 ───────────────────────────────────────────────────────────────
log "Installation d'AWS CLI v2..."
if ! command -v aws &>/dev/null; then
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
    unzip -q /tmp/awscliv2.zip -d /tmp/aws-install
    /tmp/aws-install/aws/install
    rm -rf /tmp/awscliv2.zip /tmp/aws-install
    log "AWS CLI installé : $(aws --version)"
else
    log "AWS CLI déjà installé : $(aws --version)"
fi

# ── kubectl ──────────────────────────────────────────────────────────────────
log "Installation de kubectl..."
if ! command -v kubectl &>/dev/null; then
    KUBECTL_VERSION=$(curl -fsSL "https://dl.k8s.io/release/stable.txt")
    curl -fsSLo /usr/local/bin/kubectl \
        "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
    chmod +x /usr/local/bin/kubectl
    log "kubectl installé : $(kubectl version --client --short 2>/dev/null || kubectl version --client)"
else
    log "kubectl déjà installé"
fi

# ── minikube ─────────────────────────────────────────────────────────────────
log "Installation de minikube..."
if ! command -v minikube &>/dev/null; then
    curl -fsSLo /usr/local/bin/minikube \
        "https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64"
    chmod +x /usr/local/bin/minikube
    log "minikube installé : $(minikube version --short)"
else
    log "minikube déjà installé"
fi

# ── Ansible ──────────────────────────────────────────────────────────────────
log "Installation d'Ansible..."
if ! command -v ansible &>/dev/null; then
    apt-add-repository -y ppa:ansible/ansible 2>/dev/null || true
    apt-get update -qq
    apt-get install -y -qq ansible
    log "Ansible installé : $(ansible --version | head -1)"
else
    log "Ansible déjà installé : $(ansible --version | head -1)"
fi

# ── Helm (Kubernetes package manager) ────────────────────────────────────────
log "Installation de Helm..."
if ! command -v helm &>/dev/null; then
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    log "Helm installé : $(helm version --short)"
else
    log "Helm déjà installé"
fi

# ── Variables d'environnement ─────────────────────────────────────────────────
cat >> /home/azureofppt/.bashrc << 'BASHRC'

# ── OFPPT Cloud Computing Lab ──────────────────────────────
export EDITOR=nano
alias k='kubectl'
alias tf='terraform'
alias dc='docker-compose'
alias d='docker'

# Kubectl autocompletion
source <(kubectl completion bash) 2>/dev/null || true
complete -o default -F __start_kubectl k 2>/dev/null || true
BASHRC

# ── Résumé ───────────────────────────────────────────────────────────────────
log ""
log "=== Installation Cloud Computing terminée ==="
log "Docker         : $(docker --version 2>/dev/null || echo 'N/A')"
log "Docker Compose : $(docker-compose --version 2>/dev/null || echo 'N/A')"
log "Terraform      : $(terraform version | head -1 2>/dev/null || echo 'N/A')"
log "Azure CLI      : $(az version --query '\"azure-cli\"' -o tsv 2>/dev/null || echo 'N/A')"
log "AWS CLI        : $(aws --version 2>/dev/null || echo 'N/A')"
log "kubectl        : $(kubectl version --client --short 2>/dev/null || echo 'N/A')"
log "minikube       : $(minikube version --short 2>/dev/null || echo 'N/A')"
log "Ansible        : $(ansible --version | head -1 2>/dev/null || echo 'N/A')"
log "Helm           : $(helm version --short 2>/dev/null || echo 'N/A')"
log "=== VM prête pour les TPs Cloud Computing OFPPT ==="
