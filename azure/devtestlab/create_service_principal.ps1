$az  = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd"
$SUB = "b64ddf59-d9cf-4c48-8174-27962dfc261c"
$RG  = "rg-ofppt-devtestlab"
$LAB = "ofppt-lab-formation"
$SP_NAME = "sp-ofppt-moodle-dtl"
$LAB_SCOPE = "/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.DevTestLab/labs/$LAB"

Write-Host "=== Creation Service Principal pour Moodle ===" -ForegroundColor Cyan

# Verifier si SP existe deja
Write-Host "[1] Verification SP existant..." -ForegroundColor Green
$existing = & $az ad sp list --display-name $SP_NAME --query "[0].appId" -o tsv 2>&1
if ($existing -and $existing -notmatch "WARNING") {
    Write-Host "   SP existant: $existing" -ForegroundColor Yellow
    Write-Host "   Suppression pour recreer avec nouveaux credentials..." -ForegroundColor Yellow
    & $az ad sp delete --id $existing 2>&1 | Out-Null
    Start-Sleep -Seconds 5
}

# Creer le SP avec role DevTest Labs User
Write-Host "[2] Creation SP '$SP_NAME'..." -ForegroundColor Green
$spJson = & $az ad sp create-for-rbac `
    --name $SP_NAME `
    --role "DevTest Labs User" `
    --scopes $LAB_SCOPE `
    --output json 2>&1

Write-Host "--- Credentials SP (A SAUVEGARDER) ---" -ForegroundColor Red
Write-Host $spJson -ForegroundColor White
Write-Host "--------------------------------------" -ForegroundColor Red

# Parser les valeurs
$sp = $spJson | ConvertFrom-Json
$tenantId  = $sp.tenant
$clientId  = $sp.appId
$clientSecret = $sp.password

# Ajouter aussi le role Contributor sur le RG pour lire les IPs / statuts
Write-Host "[3] Ajout role Reader sur Resource Group..." -ForegroundColor Green
& $az role assignment create `
    --assignee $clientId `
    --role "Reader" `
    --scope "/subscriptions/$SUB/resourceGroups/$RG" `
    --output none 2>&1
Write-Host "   Reader ajoute sur $RG" -ForegroundColor Green

# Verifier les roles
Write-Host "[4] Roles assignes au SP..." -ForegroundColor Green
& $az role assignment list --assignee $clientId --output table 2>&1

# Generer le snippet PHP pour config.php
Write-Host ""
Write-Host "=== SNIPPET config.php ===" -ForegroundColor Cyan
Write-Host "define('AZURE_TENANT_ID',     '$tenantId');" -ForegroundColor Yellow
Write-Host "define('AZURE_CLIENT_ID',     '$clientId');" -ForegroundColor Yellow
Write-Host "define('AZURE_CLIENT_SECRET', '$clientSecret');" -ForegroundColor Yellow
Write-Host "define('AZURE_SUBSCRIPTION_ID', '$SUB');" -ForegroundColor Yellow

# Sauvegarder dans un fichier .env (hors git)
$envContent = @"
AZURE_TENANT_ID=$tenantId
AZURE_CLIENT_ID=$clientId
AZURE_CLIENT_SECRET=$clientSecret
AZURE_SUBSCRIPTION_ID=$SUB
AZURE_RESOURCE_GROUP=$RG
AZURE_LAB_NAME=$LAB
"@
$envFile = "C:\Users\Administrateur\Desktop\ofppt-lab\moodle\devtestlab_integration\.env.local"
[System.IO.File]::WriteAllText($envFile, $envContent, [System.Text.Encoding]::UTF8)
Write-Host ""
Write-Host "Credentials sauvegardes dans: $envFile" -ForegroundColor Green
Write-Host "(fichier local uniquement - ne pas commiter)" -ForegroundColor Yellow
