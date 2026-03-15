$az  = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd"
$RG  = "rg-ofppt-devtestlab"
$AA  = "aa-ofppt-dtl-stop"
$RB  = "StopVmsByDuration"
$SCH = "schedule-stop-4h"

Write-Host "[1/4] Creation runbook..." -ForegroundColor Cyan
& $az automation runbook create `
    --resource-group $RG `
    --automation-account-name $AA `
    --name $RB `
    --type PowerShell `
    --output none 2>&1

Write-Host "[2/4] Publication runbook..." -ForegroundColor Cyan
& $az automation runbook publish `
    --resource-group $RG `
    --automation-account-name $AA `
    --name $RB `
    --output none 2>&1

Write-Host "[3/4] Creation schedule 15 min..." -ForegroundColor Cyan
$startTime = (Get-Date).AddMinutes(5).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
& $az automation schedule create `
    --resource-group $RG `
    --automation-account-name $AA `
    --name $SCH `
    --frequency Minute `
    --interval 15 `
    --start-time $startTime `
    --time-zone "UTC" `
    --description "Arret VMs DTL apres 4h" `
    --output none 2>&1

Write-Host "[4/4] Liaison schedule -> runbook..." -ForegroundColor Cyan
& $az automation job-schedule create `
    --resource-group $RG `
    --automation-account-name $AA `
    --runbook-name $RB `
    --schedule-name $SCH `
    --parameters ResourceGroupName=$RG LabName="ofppt-lab-formation" MaxDurationHours=4 DryRun=false `
    --output none 2>&1

Write-Host "`n[OK] Runbook configure : $RB toutes les 15 min (max 4h par VM)" -ForegroundColor Green
& $az automation runbook show --resource-group $RG --automation-account-name $AA --name $RB --query "{nom:name,statut:state}" -o table 2>&1
