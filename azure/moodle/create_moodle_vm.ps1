# =============================================================================
# create_moodle_vm.ps1 -- Creation VM Azure pour serveur Moodle PROD
# =============================================================================
# Cree une VM Ubuntu 22.04 (Standard_D2s_v3) en France Central
# avec NSG : ports 22 (SSH), 80 (HTTP), 443 (HTTPS)
#
# Usage :
#   powershell -ExecutionPolicy Bypass -File azure\moodle\create_moodle_vm.ps1
# =============================================================================

$ErrorActionPreference = "Stop"
$AZ = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd"

# -- Parametres ---------------------------------------------------------------
$SUBSCRIPTION  = "b64ddf59-d9cf-4c48-8174-27962dfc261c"
$RG            = "rg-ofppt-moodle-prod"
$LOCATION      = "francecentral"
$VM_NAME       = "OFPPT-ACADEMY-LMS"
$VM_SIZE       = "Standard_D2s_v3"
$ADMIN_USER    = "azureofppt"
$ADMIN_PASS    = "Ofppt@lab2026!"
$NSG_NAME      = "nsg-ofppt-academy-lms"
$PIP_NAME      = "pip-ofppt-academy-lms"
$DNS_LABEL     = "ofppt-academy-lms"
$VNET_NAME     = "vnet-moodle-prod"
$SUBNET_NAME   = "subnet-moodle"

Write-Host ""
Write-Host "=== OFPPT Academy -- Creation VM Moodle PROD ===" -ForegroundColor Cyan
Write-Host ""

# -- Subscription -------------------------------------------------------------
Write-Host "[1/7] Selecting subscription..." -ForegroundColor Yellow
& $AZ account set --subscription $SUBSCRIPTION
Write-Host "OK" -ForegroundColor Green

# -- Resource Group -----------------------------------------------------------
Write-Host "[2/7] Creating resource group $RG..." -ForegroundColor Yellow
& $AZ group create --name $RG --location $LOCATION --output none
Write-Host "OK" -ForegroundColor Green

# -- VNet + Subnet ------------------------------------------------------------
Write-Host "[3/7] Creating VNet + Subnet..." -ForegroundColor Yellow
& $AZ network vnet create `
    --resource-group $RG `
    --name $VNET_NAME `
    --address-prefix "10.1.0.0/16" `
    --subnet-name $SUBNET_NAME `
    --subnet-prefix "10.1.0.0/24" `
    --location $LOCATION `
    --output none
Write-Host "OK" -ForegroundColor Green

# -- NSG + Rules --------------------------------------------------------------
Write-Host "[4/7] Creating NSG with rules SSH/HTTP/HTTPS..." -ForegroundColor Yellow
& $AZ network nsg create `
    --resource-group $RG `
    --name $NSG_NAME `
    --location $LOCATION `
    --output none

# SSH port 22
& $AZ network nsg rule create `
    --resource-group $RG `
    --nsg-name $NSG_NAME `
    --name "Allow-SSH" `
    --protocol Tcp `
    --direction Inbound `
    --priority 100 `
    --source-address-prefix "*" `
    --source-port-range "*" `
    --destination-address-prefix "*" `
    --destination-port-range 22 `
    --access Allow `
    --output none

# HTTP port 80
& $AZ network nsg rule create `
    --resource-group $RG `
    --nsg-name $NSG_NAME `
    --name "Allow-HTTP" `
    --protocol Tcp `
    --direction Inbound `
    --priority 110 `
    --source-address-prefix "*" `
    --source-port-range "*" `
    --destination-address-prefix "*" `
    --destination-port-range 80 `
    --access Allow `
    --output none

# HTTPS port 443
& $AZ network nsg rule create `
    --resource-group $RG `
    --nsg-name $NSG_NAME `
    --name "Allow-HTTPS" `
    --protocol Tcp `
    --direction Inbound `
    --priority 120 `
    --source-address-prefix "*" `
    --source-port-range "*" `
    --destination-address-prefix "*" `
    --destination-port-range 443 `
    --access Allow `
    --output none

Write-Host "OK -- NSG $NSG_NAME cree (SSH:22, HTTP:80, HTTPS:443)" -ForegroundColor Green

# -- Public IP with DNS label -------------------------------------------------
Write-Host "[5/7] Creating Public IP ($DNS_LABEL)..." -ForegroundColor Yellow
& $AZ network public-ip create `
    --resource-group $RG `
    --name $PIP_NAME `
    --location $LOCATION `
    --sku Standard `
    --allocation-method Static `
    --dns-name $DNS_LABEL `
    --output none
Write-Host "OK" -ForegroundColor Green

# -- NIC with NSG + Public IP -------------------------------------------------
Write-Host "[6/7] Creating NIC..." -ForegroundColor Yellow
$NIC_NAME = "nic-ofppt-academy-lms"
& $AZ network nic create `
    --resource-group $RG `
    --name $NIC_NAME `
    --vnet-name $VNET_NAME `
    --subnet $SUBNET_NAME `
    --network-security-group $NSG_NAME `
    --public-ip-address $PIP_NAME `
    --location $LOCATION `
    --output none
Write-Host "OK" -ForegroundColor Green

# -- VM Creation --------------------------------------------------------------
Write-Host "[7/7] Creating VM $VM_NAME ($VM_SIZE)..." -ForegroundColor Yellow
Write-Host "  (peut prendre 3-5 minutes...)" -ForegroundColor Gray

& $AZ vm create `
    --resource-group $RG `
    --name $VM_NAME `
    --nics $NIC_NAME `
    --image Ubuntu2204 `
    --size $VM_SIZE `
    --admin-username $ADMIN_USER `
    --admin-password $ADMIN_PASS `
    --authentication-type password `
    --os-disk-size-gb 64 `
    --storage-sku StandardSSD_LRS `
    --no-wait `
    --output none

Write-Host "  VM en cours de creation (--no-wait)..." -ForegroundColor Gray
Write-Host "  Attente provisioning (60s)..." -ForegroundColor Gray
Start-Sleep -Seconds 60

# Poll until succeeded
$maxWait = 300
$elapsed = 60
while ($elapsed -lt $maxWait) {
    $state = & $AZ vm show --resource-group $RG --name $VM_NAME `
        --query "provisioningState" -o tsv 2>$null
    if ($state -eq "Succeeded") { break }
    if ($state -eq "Failed")    { Write-Host "ERREUR: VM provisionning Failed" -ForegroundColor Red; exit 1 }
    Write-Host "  Etat: $state -- attente 15s..." -ForegroundColor Gray
    Start-Sleep -Seconds 15
    $elapsed += 15
}

Write-Host "OK -- VM creee avec succes !" -ForegroundColor Green

# -- Infos de connexion -------------------------------------------------------
$FQDN = & $AZ network public-ip show `
    --resource-group $RG `
    --name $PIP_NAME `
    --query "dnsSettings.fqdn" -o tsv

$IP = & $AZ network public-ip show `
    --resource-group $RG `
    --name $PIP_NAME `
    --query "ipAddress" -o tsv

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  VM Moodle PROD creee avec succes !" -ForegroundColor Green
Write-Host "============================================================"
Write-Host ""
Write-Host "  VM Name        : $VM_NAME"
Write-Host "  Resource Group : $RG"
Write-Host "  Taille         : $VM_SIZE"
Write-Host "  IP publique    : $IP"
Write-Host "  FQDN           : $FQDN"
Write-Host ""
Write-Host "  Connexion SSH  :" -ForegroundColor Yellow
Write-Host "  ssh ${ADMIN_USER}@${FQDN}"
Write-Host "    ou"
Write-Host "  ssh ${ADMIN_USER}@${IP}"
Write-Host ""
Write-Host "  Prochaine etape :"
Write-Host "  1. Exporter Moodle depuis Vagrant :"
Write-Host "     vagrant ssh vm-cloud -- 'sudo bash /vagrant/moodle/migration/01_export_vagrant.sh'"
Write-Host "  2. Transferer l'archive sur Azure VM :"
Write-Host "     scp moodle-migration.tar.gz ${ADMIN_USER}@${FQDN}:/home/${ADMIN_USER}/"
Write-Host "  3. Installer Moodle sur Azure VM :"
Write-Host "     ssh ${ADMIN_USER}@${FQDN} 'sudo bash /home/${ADMIN_USER}/02_install_moodle_azure.sh'"
Write-Host ""
Write-Host "  NOTE DNS : configurer moodle.ofppt-academy.ma -> $IP" -ForegroundColor Yellow
Write-Host ""

# Sauvegarder les infos dans un fichier local
$infoFile = "$PSScriptRoot\moodle_vm_info.txt"
@"
VM_NAME=$VM_NAME
RESOURCE_GROUP=$RG
IP=$IP
FQDN=$FQDN
ADMIN_USER=$ADMIN_USER
LOCATION=$LOCATION
VM_SIZE=$VM_SIZE
CREATED=$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
"@ | Out-File -FilePath $infoFile -Encoding UTF8
Write-Host "  Infos sauvegardees : $infoFile" -ForegroundColor Gray
