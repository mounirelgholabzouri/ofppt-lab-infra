# create_nsg_vm_admin.ps1 — Cree NSG + attache a vm-admin-cc101t (nouveau RG)
$az        = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd"
$computeRG = "ofppt-lab-formation-vm-admin-cc101t-017751"
$vmName    = "vm-admin-cc101t"
$nsgName   = "nsg-$vmName"
$location  = "francecentral"

Write-Host "[1] Creation NSG '$nsgName'..." -ForegroundColor Green
& $az network nsg create `
    --resource-group $computeRG `
    --name $nsgName `
    --location $location `
    -o none 2>&1
Write-Host "  NSG cree"

Write-Host "[2] Regles NSG (SSH:22 + ttyd:7681 + HTTP:80)..." -ForegroundColor Green
& $az network nsg rule create --resource-group $computeRG --nsg-name $nsgName `
    --name Allow-SSH  --priority 100 --protocol Tcp `
    --destination-port-ranges 22   --access Allow --direction Inbound -o none 2>&1
& $az network nsg rule create --resource-group $computeRG --nsg-name $nsgName `
    --name Allow-ttyd --priority 110 --protocol Tcp `
    --destination-port-ranges 7681 --access Allow --direction Inbound -o none 2>&1
& $az network nsg rule create --resource-group $computeRG --nsg-name $nsgName `
    --name Allow-HTTP --priority 120 --protocol Tcp `
    --destination-port-ranges 80   --access Allow --direction Inbound -o none 2>&1
Write-Host "  3 regles creees"

Write-Host "[3] Attachement NSG a la NIC '$vmName'..." -ForegroundColor Green
& $az network nic update `
    --resource-group $computeRG `
    --name $vmName `
    --network-security-group $nsgName `
    -o none 2>&1
Write-Host "  NIC mise a jour avec NSG"

Write-Host ""
Write-Host "=== NSG OK ===" -ForegroundColor Green
Write-Host "  SSH  : ssh azureofppt@vm-admin-cc101t.francecentral.cloudapp.azure.com"
Write-Host "  ttyd : http://vm-admin-cc101t.francecentral.cloudapp.azure.com:7681"
Write-Host "  IP   : 20.216.128.34"
