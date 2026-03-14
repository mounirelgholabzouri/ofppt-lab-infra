$az  = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd"
$SUB = "b64ddf59-d9cf-4c48-8174-27962dfc261c"
$RG  = "rg-ofppt-devtestlab"
$LAB = "ofppt-lab-formation"

# Credentials crees lors de l'etape precedente
$tenantId     = "687d3cdf-7038-4560-a9f5-b3f0403eb863"
$clientId     = "ae328530-c971-44a9-98dc-443f0618b4fc"
$clientSecret = $env:AZURE_CLIENT_SECRET  # Charger depuis variable d'environnement ou .env.local
$SP_NAME      = "sp-ofppt-moodle-dtl"

Write-Host "=== Configuration roles SP ===" -ForegroundColor Cyan
Write-Host "SP  : $SP_NAME" -ForegroundColor White
Write-Host "ID  : $clientId" -ForegroundColor White

# Attendre que le SP soit propagé dans AAD
Write-Host "[1] Attente propagation AAD (15s)..." -ForegroundColor Yellow
Start-Sleep -Seconds 15

# Ajout role Reader sur le Resource Group
Write-Host "[2] Role Reader sur RG $RG..." -ForegroundColor Green
& $az role assignment create `
    --assignee $clientId `
    --role "Reader" `
    --scope "/subscriptions/$SUB/resourceGroups/$RG" `
    --output none 2>&1
Write-Host "   Reader OK" -ForegroundColor Green

# Verifier les assignations
Write-Host "[3] Verification roles..." -ForegroundColor Green
& $az role assignment list `
    --assignee $clientId `
    --output table 2>&1

# Sauvegarder les credentials dans .env.local
Write-Host "[4] Sauvegarde credentials..." -ForegroundColor Green
$envContent = "AZURE_TENANT_ID=$tenantId`nAZURE_CLIENT_ID=$clientId`nAZURE_CLIENT_SECRET=$clientSecret`nAZURE_SUBSCRIPTION_ID=$SUB`nAZURE_RESOURCE_GROUP=$RG`nAZURE_LAB_NAME=$LAB"
$envFile = "C:\Users\Administrateur\Desktop\ofppt-lab\moodle\devtestlab_integration\.env.local"
[System.IO.File]::WriteAllText($envFile, $envContent, [System.Text.Encoding]::UTF8)
Write-Host "   Credentials sauvegardes: $envFile" -ForegroundColor Green

Write-Host ""
Write-Host "=== SNIPPET pour config.php ===" -ForegroundColor Cyan
Write-Host "define('AZURE_TENANT_ID',     '$tenantId');" -ForegroundColor Yellow
Write-Host "define('AZURE_CLIENT_ID',     '$clientId');" -ForegroundColor Yellow
Write-Host "define('AZURE_CLIENT_SECRET', '$clientSecret');" -ForegroundColor Yellow
Write-Host "define('AZURE_SUBSCRIPTION_ID', '$SUB');" -ForegroundColor Yellow
