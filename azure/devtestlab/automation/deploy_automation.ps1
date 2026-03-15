$az = 'C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd'
$RG       = "rg-ofppt-devtestlab"
$LAB      = "ofppt-lab-formation"
$LOCATION = "francecentral"
$AA_NAME  = "aa-ofppt-dtl-stop"
$RUNBOOK  = "StopVmsByDuration"
$SCRIPT   = "$PSScriptRoot\..\runbook_stop_by_duration.ps1"

Write-Host "`n[AUTOMATION] Déploiement Azure Automation Account..." -ForegroundColor Cyan

# 1. Créer l'Automation Account
Write-Host "[1/5] Création de l'Automation Account..." -ForegroundColor Green
& $az automation account create `
    --resource-group $RG `
    --name $AA_NAME `
    --location $LOCATION `
    --sku Basic `
    --output table

# 2. Activer la Managed Identity (System-Assigned)
Write-Host "[2/5] Activation de la Managed Identity..." -ForegroundColor Green
& $az automation account update `
    --resource-group $RG `
    --name $AA_NAME `
    --assign-identity '[system]' `
    --output table

# 3. Attribuer le rôle Contributor sur le Resource Group
Write-Host "[3/5] Attribution du rôle Contributor à la Managed Identity..." -ForegroundColor Green
$principalId = & $az automation account show `
    --resource-group $RG `
    --name $AA_NAME `
    --query "identity.principalId" -o tsv

$subscriptionId = & $az account show --query id -o tsv
$scope = "/subscriptions/$subscriptionId/resourceGroups/$RG"

& $az role assignment create `
    --assignee-object-id $principalId `
    --assignee-principal-type ServicePrincipal `
    --role "Contributor" `
    --scope $scope `
    --output none

Write-Host "   Role Contributor attribué à la Managed Identity ($principalId)" -ForegroundColor Green

# 4. Importer le Runbook PowerShell
Write-Host "[4/5] Import du Runbook '$RUNBOOK'..." -ForegroundColor Green
& $az automation runbook create `
    --resource-group $RG `
    --automation-account-name $AA_NAME `
    --name $RUNBOOK `
    --type PowerShell `
    --output none

& $az automation runbook replace-content `
    --resource-group $RG `
    --automation-account-name $AA_NAME `
    --name $RUNBOOK `
    --content (Get-Content $SCRIPT -Raw) `
    --output none

& $az automation runbook publish `
    --resource-group $RG `
    --automation-account-name $AA_NAME `
    --name $RUNBOOK `
    --output none

Write-Host "   Runbook '$RUNBOOK' importé et publié" -ForegroundColor Green

# 5. Créer le schedule (toutes les 15 minutes)
Write-Host "[5/5] Création du schedule (toutes les 15 min)..." -ForegroundColor Green
$startTime = (Get-Date).AddMinutes(5).ToString("yyyy-MM-ddTHH:mm:ss")

& $az automation schedule create `
    --resource-group $RG `
    --automation-account-name $AA_NAME `
    --name "schedule-stop-by-duration" `
    --frequency Minute `
    --interval 15 `
    --start-time $startTime `
    --time-zone "Africa/Casablanca" `
    --description "Arrêt des VMs DevTest Labs après 4h de fonctionnement" `
    --output none

# Lier le schedule au runbook avec les paramètres
& $az automation job-schedule create `
    --resource-group $RG `
    --automation-account-name $AA_NAME `
    --runbook-name $RUNBOOK `
    --schedule-name "schedule-stop-by-duration" `
    --parameters ResourceGroupName=$RG LabName=$LAB MaxDurationHours=4 DryRun=false `
    --output none

Write-Host "`n[AUTOMATION] ✅ Déploiement terminé !" -ForegroundColor Green
Write-Host "   Automation Account : $AA_NAME" -ForegroundColor Cyan
Write-Host "   Runbook            : $RUNBOOK" -ForegroundColor Cyan
Write-Host "   Schedule           : toutes les 15 minutes" -ForegroundColor Cyan
Write-Host "   Durée max VM       : 4 heures" -ForegroundColor Cyan
