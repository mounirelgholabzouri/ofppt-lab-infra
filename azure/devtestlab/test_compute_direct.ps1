$az  = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd"
$RG  = "rg-test-compute-tmp"
$LOC = "francecentral"
$vmName = "vm-test-direct"

Write-Host "=== Test VM Compute directe (hors DTL) ===" -ForegroundColor Cyan

Write-Host "[1] Creation RG temporaire..." -ForegroundColor Green
& $az group create --name $RG --location $LOC --output none 2>&1

$sshKey = (Get-Content "C:\Users\Administrateur\.ssh\ofppt_azure.pub" -Raw).Trim()

Write-Host "[2] Creation VM Ubuntu 22.04 Standard_B2s..." -ForegroundColor Green
$result = & $az vm create `
    --resource-group $RG `
    --name $vmName `
    --image Canonical:ubuntu-22_04-lts:server-gen1:latest `
    --size Standard_B2s `
    --admin-username azureofppt `
    --ssh-key-value $sshKey `
    --public-ip-sku Basic `
    --output json 2>&1

$result | Select-Object -First 20 | ForEach-Object { Write-Host $_ }

if (($result -join "") -match '"provisioningState": "Succeeded"') {
    Write-Host ""
    Write-Host "VM COMPUTE DIRECTE : OK !" -ForegroundColor Green
    Write-Host "La subscription supporte la creation de VMs." -ForegroundColor Green

    # Nettoyage
    Write-Host "[3] Suppression RG temporaire..." -ForegroundColor Yellow
    & $az group delete --name $RG --yes --no-wait --output none 2>&1
    Write-Host "RG supprime (asynchrone)." -ForegroundColor Yellow
} else {
    Write-Host "ECHEC VM directe. Erreur subscription ou region." -ForegroundColor Red
    Write-Host "Verifier la politique de la subscription Free Trial." -ForegroundColor Red
    & $az group delete --name $RG --yes --no-wait --output none 2>&1
}
