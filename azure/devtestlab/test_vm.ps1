$az  = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd"
$RG  = "rg-ofppt-devtestlab"
$LAB = "ofppt-lab-formation"
$vmName = "test-vm-" + (Get-Date -Format "MMdd-HHmm")

Write-Host "=== Test VM DevTest Labs ===" -ForegroundColor Cyan
Write-Host "Lab: $LAB  VM: $vmName" -ForegroundColor White

$sshKey = (Get-Content "C:\Users\Administrateur\.ssh\ofppt_azure.pub" -Raw).Trim()

Write-Host "[1] Creation VM Ubuntu 18.04 (image-type gallery)..." -ForegroundColor Green
& $az lab vm create `
    --lab-name $LAB `
    --resource-group $RG `
    --name $vmName `
    --image "Canonical:UbuntuServer:18.04-LTS:latest" `
    --image-type gallery `
    --size Standard_B2s `
    --authentication-type ssh `
    --ssh-key $sshKey `
    --output json 2>&1

Write-Host "[2] Statut apres 30s..." -ForegroundColor Green
Start-Sleep -Seconds 30

& $az lab vm show `
    --lab-name $LAB `
    --resource-group $RG `
    --name $vmName `
    --query "{name:name,state:properties.lastKnownPowerState,prov:properties.provisioningState}" `
    --output table 2>&1
