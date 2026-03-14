$az  = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd"
$SUB = "b64ddf59-d9cf-4c48-8174-27962dfc261c"
$VM  = "tp-test-0314-1346"

# Trouver le RG compute en listant tous les RGs
$rgsRaw = & $az rest --method GET `
    --url "https://management.azure.com/subscriptions/$SUB/resourcegroups?api-version=2021-04-01" `
    -o json 2>&1
$rgsObj = $rgsRaw | ConvertFrom-Json -ErrorAction SilentlyContinue
$computeRG = $rgsObj.value | Where-Object { $_.name -like "*$VM*" } | Select-Object -First 1
Write-Host "RG Compute: $($computeRG.name)" -ForegroundColor Cyan

if ($computeRG) {
    $rgName = $computeRG.name
    Write-Host "Resources..." -ForegroundColor Green
    & $az resource list --resource-group $rgName --output table 2>&1

    Write-Host "Deployments..." -ForegroundColor Green
    & $az deployment group list --resource-group $rgName --output table 2>&1

    Write-Host "Activity log erreurs..." -ForegroundColor Green
    & $az monitor activity-log list `
        --resource-group $rgName `
        --caller "Microsoft.DevTestLab" `
        --max-events 10 `
        --output table 2>&1
}

Write-Host "PIPs dans l'abonnement..." -ForegroundColor Cyan
& $az rest --method GET `
    --url "https://management.azure.com/subscriptions/$SUB/providers/Microsoft.Network/publicIPAddresses?api-version=2023-09-01" `
    --query "value[].{name:name,rg:resourceGroup}" `
    --output table 2>&1

Write-Host "Quota PIPs francecentral..." -ForegroundColor Cyan
& $az network list-usages --location francecentral `
    --query "[?contains(name.value,'PublicIP') || contains(name.value,'publicIP')].{name:name.localizedValue,used:currentValue,limit:limit}" `
    --output table 2>&1
