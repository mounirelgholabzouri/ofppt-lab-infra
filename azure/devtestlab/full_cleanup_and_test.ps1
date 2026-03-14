$az  = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd"
$SUB = "b64ddf59-d9cf-4c48-8174-27962dfc261c"
$RG  = "rg-ofppt-devtestlab"
$LAB = "ofppt-lab-formation"
$BASE = "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.DevTestLab/labs/$LAB"

Write-Host "=== Nettoyage complet + test VM ===" -ForegroundColor Cyan

# 1. Supprimer toutes les VMs du lab
Write-Host "[1] Suppression toutes VMs du lab..." -ForegroundColor Yellow
$allVMs = (& $az rest --method GET `
    --url "$BASE/virtualmachines?api-version=2018-09-15" `
    --query "value[].name" -o tsv 2>&1)
$allVMs | ForEach-Object {
    $vmn = $_.Trim()
    if ($vmn) {
        Write-Host "   Suppression: $vmn" -ForegroundColor Gray
        & $az rest --method DELETE --url "$BASE/virtualmachines/${vmn}?api-version=2018-09-15" --output none 2>&1 | Out-Null
    }
}

# 2. Supprimer tous les RGs Compute DTL
Write-Host "[2] Suppression RGs Compute orphelins..." -ForegroundColor Yellow
$rgsObj = (& $az rest --method GET `
    --url "https://management.azure.com/subscriptions/$SUB/resourcegroups?api-version=2021-04-01" `
    -o json 2>&1) | ConvertFrom-Json -ErrorAction SilentlyContinue
$dtlRGs = $rgsObj.value | Where-Object { $_.name -like "ofppt-lab-formation-*" }
$dtlRGs | ForEach-Object {
    Write-Host "   Suppression RG: $($_.name)" -ForegroundColor Gray
    & $az group delete --name $_.name --yes --no-wait --output none 2>&1 | Out-Null
}

Write-Host "[3] Attente 60s propagation..." -ForegroundColor Yellow
Start-Sleep -Seconds 60

# 3. Verifier que le lab est vide
Write-Host "[4] VMs dans le lab maintenant..." -ForegroundColor Green
$remaining = (& $az rest --method GET `
    --url "$BASE/virtualmachines?api-version=2018-09-15" `
    --query "value[].name" -o tsv 2>&1)
Write-Host "VMs restantes: $remaining" -ForegroundColor White

# 4. Verifier PIPs
Write-Host "[5] PIPs restants..." -ForegroundColor Green
$pips = & $az rest --method GET `
    --url "https://management.azure.com/subscriptions/$SUB/providers/Microsoft.Network/publicIPAddresses?api-version=2023-09-01" `
    --query "value[].name" -o tsv 2>&1
Write-Host "PIPs: $pips" -ForegroundColor White

# 5. Creer la VM avec D2s_v3
$vmName = "tp-d2-" + (Get-Date -Format "MMdd-HHmm")
Write-Host "[6] Creation VM $vmName (D2s_v3)..." -ForegroundColor Green

$dtlVnetId = (& $az rest --method GET `
    --url "$BASE/virtualnetworks?api-version=2018-09-15" `
    --query "value[0].id" -o tsv 2>&1).Trim()

$vmBody = @{
    name     = $vmName
    location = "francecentral"
    tags     = @{}
    properties = @{
        size               = "Standard_D2s_v3"
        userName           = "azureofppt"
        password           = "Ofppt@lab2026!"
        isAuthenticationWithSshKey = $false
        allowClaim         = $false
        disallowPublicIpAddress = $false
        storageType        = "Standard"
        labVirtualNetworkId = $dtlVnetId
        labSubnetName      = "subnet-ofppt-dtl"
        galleryImageReference = @{
            offer     = "ubuntu-22_04-lts"
            publisher = "Canonical"
            sku       = "server-gen1"
            osType    = "Linux"
            version   = "latest"
        }
    }
}
$vmFile = "$env:TEMP\ofppt_vm_final.json"
[System.IO.File]::WriteAllText($vmFile, ($vmBody | ConvertTo-Json -Depth 10 -Compress), [System.Text.Encoding]::UTF8)
$r = & $az rest --method PUT `
    --url "$BASE/virtualmachines/${vmName}?api-version=2018-09-15" `
    --body "@$vmFile" `
    --headers "Content-Type=application/json" 2>&1
Remove-Item $vmFile -ErrorAction SilentlyContinue

if (($r -join "") -match "ERROR") {
    Write-Host "ERREUR creation: $($r | Select-Object -First 2)" -ForegroundColor Red
    exit 1
}
Write-Host "Creation lancee." -ForegroundColor Green

for ($i = 1; $i -le 10; $i++) {
    Start-Sleep -Seconds 30
    $stObj = & $az rest --method GET `
        --url "$BASE/virtualmachines/${vmName}?api-version=2018-09-15" `
        --query "{prov:properties.provisioningState,fqdn:properties.fqdn}" `
        -o json 2>&1 | ConvertFrom-Json -ErrorAction SilentlyContinue
    Write-Host "  [${i}] prov=$($stObj.prov)  fqdn=$($stObj.fqdn)" -ForegroundColor White
    if ($stObj.prov -eq "Succeeded" -or $stObj.prov -eq "Failed") { break }
}

$final = & $az rest --method GET `
    --url "$BASE/virtualmachines/${vmName}?api-version=2018-09-15" `
    --query "{prov:properties.provisioningState,fqdn:properties.fqdn}" `
    -o json 2>&1 | ConvertFrom-Json -ErrorAction SilentlyContinue

Write-Host ""
if ($final.prov -eq "Succeeded" -and $final.fqdn) {
    $fqdn = $final.fqdn
    Write-Host "VM CREEE AVEC SUCCES !" -ForegroundColor Green
    Write-Host "FQDN  : $fqdn" -ForegroundColor Green
    Write-Host "SSH   : ssh azureofppt@$fqdn" -ForegroundColor Yellow
    Write-Host "ttyd  : http://${fqdn}:7681" -ForegroundColor Yellow
    $tcp22 = Test-NetConnection -ComputerName $fqdn -Port 22 -WarningAction SilentlyContinue
    Write-Host "Port 22 : $($tcp22.TcpTestSucceeded)" -ForegroundColor White
} else {
    Write-Host "Prov: $($final.prov)" -ForegroundColor Red
}
