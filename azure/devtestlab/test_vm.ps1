$az  = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd"
$RG  = "rg-ofppt-devtestlab"
$LAB = "ofppt-lab-formation"
$vmName = "test-vm-" + (Get-Date -Format "MMdd-HHmm")

Write-Host "=== Test VM DevTest Labs ===" -ForegroundColor Cyan
Write-Host "Lab   : $LAB" -ForegroundColor White
Write-Host "VM    : $vmName" -ForegroundColor White

# SSH key
$sshPubFile = "C:\Users\Administrateur\.ssh\ofppt_azure.pub"
if (Test-Path $sshPubFile) {
    $sshKey = (Get-Content $sshPubFile -Raw).Trim()
    Write-Host "SSH   : cle trouvee" -ForegroundColor White
} else {
    Write-Host "SSH   : cle non trouvee" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "[1] Creation VM depuis image Ubuntu..." -ForegroundColor Green
& $az lab vm create `
    --lab-name $LAB `
    --resource-group $RG `
    --name $vmName `
    --image "Canonical:UbuntuServer:18.04-LTS:latest" `
    --image-type GalleryImage `
    --size Standard_B2s `
    --authentication-type ssh `
    --ssh-key $sshKey `
    --output json 2>&1

Write-Host ""
Write-Host "[2] Attente 30s puis verification..." -ForegroundColor Green
Start-Sleep -Seconds 30

& $az lab vm show `
    --lab-name $LAB `
    --resource-group $RG `
    --name $vmName `
    --query "{name:name, state:properties.lastKnownPowerState, ip:properties.fqdn, status:properties.provisioningState}" `
    --output table 2>&1

Write-Host ""
Write-Host "[3] Liste VMs dans le lab..." -ForegroundColor Green
& $az lab vm list `
    --lab-name $LAB `
    --resource-group $RG `
    --output table 2>&1
