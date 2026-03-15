$az  = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd"
$SUB = "b64ddf59-d9cf-4c48-8174-27962dfc261c"
$RG  = "rg-ofppt-devtestlab"
$LAB = "ofppt-lab-formation"
$VM  = "tp-d2-0314-1401"
$BASE = "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.DevTestLab/labs/$LAB"

Write-Host "=== Suppression VM DTL : $VM ===" -ForegroundColor Yellow

# Supprimer la VM dans DTL
$r = & $az rest --method DELETE `
    --url "$BASE/virtualmachines/${VM}?api-version=2018-09-15" `
    -o json 2>&1
Write-Host "DELETE lance: $($r | Select-Object -First 2)" -ForegroundColor White

Write-Host "Attente 30s..." -ForegroundColor Gray
Start-Sleep -Seconds 30

# Verifier que la VM n'existe plus
$check = & $az rest --method GET `
    --url "$BASE/virtualmachines?api-version=2018-09-15" `
    --query "value[].{name:name,prov:properties.provisioningState}" `
    --output table 2>&1
Write-Host "VMs restantes dans le lab:" -ForegroundColor Cyan
Write-Host $check

# Supprimer aussi le RG compute si il reste
Write-Host ""
Write-Host "Recherche RG compute orphelin..." -ForegroundColor Gray
$allRgs = (& $az rest --method GET `
    --url "https://management.azure.com/subscriptions/$SUB/resourcegroups?api-version=2021-04-01" `
    -o json 2>&1 | ConvertFrom-Json -ErrorAction SilentlyContinue).value
$computeRG = ($allRgs | Where-Object { $_.name -like "*$VM*" } | Select-Object -First 1).name
if ($computeRG) {
    Write-Host "Suppression RG compute: $computeRG" -ForegroundColor Yellow
    & $az group delete --name $computeRG --yes --no-wait --output none 2>&1
    Write-Host "RG supprime (async)" -ForegroundColor Green
} else {
    Write-Host "Aucun RG compute orphelin trouve" -ForegroundColor Green
}

Write-Host ""
Write-Host "=== VM supprimee ===" -ForegroundColor Green
