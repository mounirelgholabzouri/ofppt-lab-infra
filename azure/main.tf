# =============================================================================
# main.tf — Infrastructure Azure OFPPT-Lab (Terraform)
# =============================================================================
# Déploie l'infrastructure complète via Terraform :
#   - Resource Group
#   - Virtual Network + Subnets
#   - Network Security Groups
#   - Public IPs + NICs
#   - VMs : Moodle, Guacamole, Lab Cloud/Réseau/Cyber
#   - Storage Account pour les données Moodle
# =============================================================================

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.80"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    virtual_machine {
      delete_os_disk_on_deletion = true
    }
  }
}

# ── Variables ─────────────────────────────────────────────────────────────────
variable "location" {
  description = "Région Azure"
  type        = string
  default     = "West Europe"
}

variable "project_name" {
  description = "Nom du projet"
  type        = string
  default     = "ofppt-lab"
}

variable "environment" {
  description = "Environnement (dev, staging, prod)"
  type        = string
  default     = "lab"
}

variable "admin_username" {
  description = "Nom de l'administrateur SSH"
  type        = string
  default     = "azureofppt"
}

variable "ssh_public_key_path" {
  description = "Chemin de la clé SSH publique"
  type        = string
  default     = "~/.ssh/ofppt_azure.pub"
}

variable "vm_size_web" {
  description = "Taille des VMs Web (Moodle, Guacamole)"
  type        = string
  default     = "Standard_B2s"
}

variable "vm_size_lab" {
  description = "Taille des VMs Lab"
  type        = string
  default     = "Standard_D4s_v3"
}

# ── Locals ────────────────────────────────────────────────────────────────────
locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    Owner       = "OFPPT"
    ManagedBy   = "Terraform"
  }
  rg_name = "rg-${var.project_name}-${var.environment}"
}

# ── Resource Group ────────────────────────────────────────────────────────────
resource "azurerm_resource_group" "ofppt" {
  name     = local.rg_name
  location = var.location
  tags     = local.common_tags
}

# ── Virtual Network ───────────────────────────────────────────────────────────
resource "azurerm_virtual_network" "ofppt" {
  name                = "vnet-${var.project_name}"
  resource_group_name = azurerm_resource_group.ofppt.name
  location            = azurerm_resource_group.ofppt.location
  address_space       = ["10.0.0.0/16"]
  tags                = local.common_tags
}

# ── Sous-réseaux ──────────────────────────────────────────────────────────────
resource "azurerm_subnet" "web" {
  name                 = "subnet-web"
  resource_group_name  = azurerm_resource_group.ofppt.name
  virtual_network_name = azurerm_virtual_network.ofppt.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_subnet" "lab" {
  name                 = "subnet-lab"
  resource_group_name  = azurerm_resource_group.ofppt.name
  virtual_network_name = azurerm_virtual_network.ofppt.name
  address_prefixes     = ["10.0.2.0/24"]
}

resource "azurerm_subnet" "mgmt" {
  name                 = "subnet-mgmt"
  resource_group_name  = azurerm_resource_group.ofppt.name
  virtual_network_name = azurerm_virtual_network.ofppt.name
  address_prefixes     = ["10.0.3.0/24"]
}

# ── Network Security Group — Web ─────────────────────────────────────────────
resource "azurerm_network_security_group" "web" {
  name                = "nsg-web-${var.project_name}"
  resource_group_name = azurerm_resource_group.ofppt.name
  location            = azurerm_resource_group.ofppt.location
  tags                = local.common_tags

  security_rule {
    name                       = "Allow-SSH"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Allow-HTTP"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Allow-HTTPS"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Allow-Guacamole"
    priority                   = 130
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "8080"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "web" {
  subnet_id                 = azurerm_subnet.web.id
  network_security_group_id = azurerm_network_security_group.web.id
}

# ── Network Security Group — Lab ──────────────────────────────────────────────
resource "azurerm_network_security_group" "lab" {
  name                = "nsg-lab-${var.project_name}"
  resource_group_name = azurerm_resource_group.ofppt.name
  location            = azurerm_resource_group.ofppt.location
  tags                = local.common_tags

  security_rule {
    name                       = "Allow-Internal"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "10.0.0.0/16"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "lab" {
  subnet_id                 = azurerm_subnet.lab.id
  network_security_group_id = azurerm_network_security_group.lab.id
}

# ── IPs Publiques ─────────────────────────────────────────────────────────────
resource "azurerm_public_ip" "moodle" {
  name                = "pip-moodle-${var.project_name}"
  resource_group_name = azurerm_resource_group.ofppt.name
  location            = azurerm_resource_group.ofppt.location
  allocation_method   = "Static"
  sku                 = "Standard"
  domain_name_label   = "moodle-${var.project_name}"
  tags                = local.common_tags
}

resource "azurerm_public_ip" "guacamole" {
  name                = "pip-guacamole-${var.project_name}"
  resource_group_name = azurerm_resource_group.ofppt.name
  location            = azurerm_resource_group.ofppt.location
  allocation_method   = "Static"
  sku                 = "Standard"
  domain_name_label   = "guacamole-${var.project_name}"
  tags                = local.common_tags
}

# ── Interfaces Réseau ─────────────────────────────────────────────────────────
resource "azurerm_network_interface" "moodle" {
  name                = "nic-vm-moodle"
  resource_group_name = azurerm_resource_group.ofppt.name
  location            = azurerm_resource_group.ofppt.location
  tags                = local.common_tags

  ip_configuration {
    name                          = "ipconfig-moodle"
    subnet_id                     = azurerm_subnet.web.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.0.1.10"
    public_ip_address_id          = azurerm_public_ip.moodle.id
  }
}

resource "azurerm_network_interface" "guacamole" {
  name                = "nic-vm-guacamole"
  resource_group_name = azurerm_resource_group.ofppt.name
  location            = azurerm_resource_group.ofppt.location
  tags                = local.common_tags

  ip_configuration {
    name                          = "ipconfig-guac"
    subnet_id                     = azurerm_subnet.web.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.0.1.20"
    public_ip_address_id          = azurerm_public_ip.guacamole.id
  }
}

resource "azurerm_network_interface" "lab" {
  name                = "nic-vm-lab"
  resource_group_name = azurerm_resource_group.ofppt.name
  location            = azurerm_resource_group.ofppt.location
  tags                = local.common_tags

  ip_configuration {
    name                          = "ipconfig-lab"
    subnet_id                     = azurerm_subnet.lab.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.0.2.10"
  }
}

# ── VM Moodle ─────────────────────────────────────────────────────────────────
resource "azurerm_linux_virtual_machine" "moodle" {
  name                  = "vm-moodle"
  resource_group_name   = azurerm_resource_group.ofppt.name
  location              = azurerm_resource_group.ofppt.location
  size                  = var.vm_size_web
  admin_username        = var.admin_username
  network_interface_ids = [azurerm_network_interface.moodle.id]
  tags                  = merge(local.common_tags, { Role = "Moodle" })

  admin_ssh_key {
    username   = var.admin_username
    public_key = file(var.ssh_public_key_path)
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = 64
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  custom_data = base64encode(file("${path.module}/../moodle/install_moodle.sh"))
}

# ── VM Guacamole ──────────────────────────────────────────────────────────────
resource "azurerm_linux_virtual_machine" "guacamole" {
  name                  = "vm-guacamole"
  resource_group_name   = azurerm_resource_group.ofppt.name
  location              = azurerm_resource_group.ofppt.location
  size                  = var.vm_size_web
  admin_username        = var.admin_username
  network_interface_ids = [azurerm_network_interface.guacamole.id]
  tags                  = merge(local.common_tags, { Role = "Guacamole" })

  admin_ssh_key {
    username   = var.admin_username
    public_key = file(var.ssh_public_key_path)
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = 32
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  custom_data = base64encode(file("${path.module}/../guacamole/install_guacamole.sh"))
}

# ── VM Lab ────────────────────────────────────────────────────────────────────
resource "azurerm_linux_virtual_machine" "lab" {
  name                  = "vm-lab"
  resource_group_name   = azurerm_resource_group.ofppt.name
  location              = azurerm_resource_group.ofppt.location
  size                  = var.vm_size_lab
  admin_username        = var.admin_username
  network_interface_ids = [azurerm_network_interface.lab.id]
  tags                  = merge(local.common_tags, { Role = "Lab" })

  admin_ssh_key {
    username   = var.admin_username
    public_key = file(var.ssh_public_key_path)
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = 128
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }
}

# ── Storage Account (données Moodle) ──────────────────────────────────────────
resource "random_string" "storage_suffix" {
  length  = 6
  special = false
  upper   = false
}

resource "azurerm_storage_account" "moodle_data" {
  name                     = "stofppt${random_string.storage_suffix.result}"
  resource_group_name      = azurerm_resource_group.ofppt.name
  location                 = azurerm_resource_group.ofppt.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"
  tags                     = local.common_tags
}

resource "azurerm_storage_container" "moodle_files" {
  name                  = "moodle-files"
  storage_account_name  = azurerm_storage_account.moodle_data.name
  container_access_type = "private"
}

# ── Outputs ───────────────────────────────────────────────────────────────────
output "moodle_public_ip" {
  description = "IP publique de la VM Moodle"
  value       = azurerm_public_ip.moodle.ip_address
}

output "moodle_url" {
  description = "URL de la plateforme Moodle"
  value       = "http://${azurerm_public_ip.moodle.ip_address}/moodle"
}

output "guacamole_public_ip" {
  description = "IP publique de la VM Guacamole"
  value       = azurerm_public_ip.guacamole.ip_address
}

output "guacamole_url" {
  description = "URL de la passerelle Guacamole"
  value       = "http://${azurerm_public_ip.guacamole.ip_address}:8080/guacamole"
}

output "lab_private_ip" {
  description = "IP privée de la VM Lab"
  value       = azurerm_network_interface.lab.private_ip_address
}

output "resource_group_name" {
  description = "Nom du Resource Group Azure"
  value       = azurerm_resource_group.ofppt.name
}

output "storage_account_name" {
  description = "Nom du compte de stockage"
  value       = azurerm_storage_account.moodle_data.name
}

output "ssh_command_moodle" {
  description = "Commande SSH pour se connecter à la VM Moodle"
  value       = "ssh -i ~/.ssh/ofppt_azure ${var.admin_username}@${azurerm_public_ip.moodle.ip_address}"
}
