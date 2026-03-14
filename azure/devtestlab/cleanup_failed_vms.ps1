$az  = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd"
$SUB = "b64ddf59-d9cf-4c48-8174-27962dfc261c"
$RG  = "rg-ofppt-devtestlab"
$LAB = "ofppt-lab-formation"
$BASE = "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.DevTestLab/labs/$LAB"

Write-Host "=== Nettoyage VMs Failed + PIPs orphelins ===" -ForegroundColor Cyan

# 1. Supprimer les VMs Failed dans DTL
Write-Host "[1] Suppression VMs Failed dans DTL..." -ForegroundColor Green
$vmsRaw = & $az rest --method GET `
    --url "$BASE/virtualmachines?api-version=2018-09-15" `
    --query "value[?properties.provisioningState=='Failed'].name" -o tsv 2>&1
$vmsRaw | ForEach-Object {
    $vmn = $_.Trim()
    if ($vmn) {
        Write-Host "   Suppression DTL VM: $vmn" -ForegroundColor Yellow
        & $az rest --method DELETE `
            --url "$BASE/virtualmachines/${vmn}?api-version=2018-09-15" `
            --output none 2>&1
        Write-Host "   Supprimee: $vmn" -ForegroundColor Gray
    }
}

# 2. Lister tous les RGs compute orphelins (format: ofppt-lab-formation-XXXX)
Write-Host "[2] RGs Compute orphelins..." -ForegroundColor Green
$allRGs = & $az rest --method GET `
    --url "https://management.azure.com/subscriptions/$SUB/resourcegroups?api-version=2021-04-01" `
    -o json 2>&1
$rgsObj = $allRGs | ConvertFrom-Json -ErrorAction SilentlyContinue
$dtlRGs = $rgsObj.value | Where-Object { $_.name -like "ofppt-lab-formation-*" }
Write-Host "   RGs DTL trouves: $($dtlRGs.Count)" -ForegroundColor White
$dtlRGs | ForEach-Object { Write-Host "   - $($_.name)" -ForegroundColor Gray }

# 3. Supprimer chaque RG compute orphelin
Write-Host "[3] Suppression RGs Compute orphelins..." -ForegroundColor Green
$dtlRGs | ForEach-Object {
    $rgName = $_.name
    Write-Host "   Suppression RG: $rgName" -ForegroundColor Yellow
    & $az group delete --name $rgName --yes --no-wait --output none 2>&1
    Write-Host "   Lance (async): $rgName" -ForegroundColor Gray
}

Write-Host ""
Write-Host "Attente 30s pour propagation..." -ForegroundColor Yellow
Start-Sleep -Seconds 30

# 4. Verifier les PIPs restants
Write-Host "[4] PIPs restants dans l'abonnement..." -ForegroundColor Green
& $az rest --method GET `
    --url "https://management.azure.com/subscriptions/$SUB/providers/Microsoft.Network/publicIPAddresses?api-version=2023-09-01" `
    --query "value[].{name:name,rg:resourceGroup,state:properties.provisioningState}" `
    --output table 2>&1

Write-Host ""
Write-Host "Nettoyage termine." -ForegroundColor Cyan
Write-Host "Relancer test_vm_pass.ps1 pour creer une nouvelle VM." -ForegroundColor Green
