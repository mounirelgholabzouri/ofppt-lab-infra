$az  = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd"
$SUB = "b64ddf59-d9cf-4c48-8174-27962dfc261c"
$computeRG = "ofppt-lab-formation-tp-d2-0314-1401-210429"
$FQDN = "tp-d2-0314-1401.francecentral.cloudapp.azure.com"
$NSG_ID = "/subscriptions/$SUB/resourceGroups/$computeRG/providers/Microsoft.Network/networkSecurityGroups/nsg-tp-d2-0314-1401"

Write-Host "=== Association NSG a la NIC via az network nic update ===" -ForegroundColor Cyan

# Verifier que le NSG existe
$nsgCheck = & $az rest --method GET `
    --url "https://management.azure.com${NSG_ID}?api-version=2023-09-01" `
    --query "name" -o tsv 2>&1
Write-Host "NSG existant: $nsgCheck" -ForegroundColor White

# Associer le NSG a la NIC
Write-Host "[1] Mise a jour NIC avec NSG..." -ForegroundColor Green
$result = & $az network nic update `
    --resource-group $computeRG `
    --name tp-d2-0314-1401 `
    --network-security-group $NSG_ID `
    --output none 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "NIC mise a jour avec succes" -ForegroundColor Green
} else {
    Write-Host "Erreur: $result" -ForegroundColor Red
}

Write-Host ""
Write-Host "[2] Verification NIC..." -ForegroundColor Green
$nicCheck = & $az rest --method GET `
    --url "https://management.azure.com/subscriptions/$SUB/resourceGroups/$computeRG/providers/Microsoft.Network/networkInterfaces/tp-d2-0314-1401?api-version=2023-09-01" `
    --query "properties.networkSecurityGroup.id" -o tsv 2>&1
Write-Host "NSG associe: $nicCheck" -ForegroundColor White

Write-Host ""
Write-Host "[3] Attente propagation (20s)..." -ForegroundColor Gray
Start-Sleep -Seconds 20

Write-Host ""
Write-Host "=== Test connectivite ===" -ForegroundColor Cyan
$tcp22 = Test-NetConnection -ComputerName $FQDN -Port 22 -WarningAction SilentlyContinue
Write-Host "Port 22 (SSH)  : $($tcp22.TcpTestSucceeded)" -ForegroundColor $(if ($tcp22.TcpTestSucceeded) { "Green" } else { "Red" })
$tcp7681 = Test-NetConnection -ComputerName $FQDN -Port 7681 -WarningAction SilentlyContinue
Write-Host "Port 7681 (ttyd): $($tcp7681.TcpTestSucceeded)" -ForegroundColor $(if ($tcp7681.TcpTestSucceeded) { "Green" } else { "Red" })

if ($tcp22.TcpTestSucceeded) {
    Write-Host ""
    Write-Host "=== SSH accessible ! ===" -ForegroundColor Green
    Write-Host "Commande: ssh azureofppt@$FQDN" -ForegroundColor Yellow
    Write-Host "Password: Ofppt@lab2026!" -ForegroundColor Yellow

    Write-Host ""
    Write-Host "=== Test SSH non-interactif ===" -ForegroundColor Cyan
    $sshTest = & ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o BatchMode=yes `
        azureofppt@$FQDN "echo SSH_OK && uname -a && whoami" 2>&1
    Write-Host "SSH output: $sshTest" -ForegroundColor White
}
