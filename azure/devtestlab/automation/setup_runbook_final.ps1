$az  = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd"
$sub = "b64ddf59-d9cf-4c48-8174-27962dfc261c"
$RG  = "rg-ofppt-devtestlab"
$AA  = "aa-ofppt-dtl-stop"
$RB  = "StopVmsByDuration"
$SCH = "schedule-stop-4h"
$BASE = "https://management.azure.com/subscriptions/$sub/resourceGroups/$RG/providers/Microsoft.Automation/automationAccounts/$AA"

Write-Host "Subscription : $sub" -ForegroundColor Cyan

# 1. Creer le runbook
Write-Host "[1/3] Creation runbook $RB..." -ForegroundColor Green
$rbBody = @{
    name     = $RB
    location = "northeurope"
    properties = @{
        runbookType = "PowerShell"
        logVerbose  = $false
        logProgress = $false
        description = "Arret VMs DTL apres 4h"
    }
}
$rbJson = $rbBody | ConvertTo-Json -Depth 5 -Compress
$rbFile = "$env:TEMP\ofppt_rb.json"
[System.IO.File]::WriteAllText($rbFile, $rbJson, [System.Text.Encoding]::UTF8)
& $az rest --method PUT --url "$BASE/runbooks/${RB}?api-version=2023-11-01" --body "@$rbFile" --headers "Content-Type=application/json" --output none 2>&1
Write-Host "   Runbook cree" -ForegroundColor Green

# 2. Creer le schedule (15 min)
Write-Host "[2/3] Creation schedule 15min..." -ForegroundColor Green
$startTime = (Get-Date).ToUniversalTime().AddMinutes(10).ToString("yyyy-MM-ddTHH:mm:ssZ")
$schBody = @{
    name     = $SCH
    properties = @{
        startTime   = $startTime
        frequency   = "Minute"
        interval    = 15
        timeZone    = "UTC"
        description = "Arret VMs DTL apres 4h - toutes 15min"
    }
}
$schJson = $schBody | ConvertTo-Json -Depth 5 -Compress
$schFile = "$env:TEMP\ofppt_sch.json"
[System.IO.File]::WriteAllText($schFile, $schJson, [System.Text.Encoding]::UTF8)
& $az rest --method PUT --url "$BASE/schedules/${SCH}?api-version=2023-11-01" --body "@$schFile" --headers "Content-Type=application/json" --output none 2>&1
Write-Host "   Schedule cree" -ForegroundColor Green

# 3. Verifier la creation
Write-Host "[3/3] Verification..." -ForegroundColor Green
$rbStatus = & $az rest --method GET --url "$BASE/runbooks/${RB}?api-version=2023-11-01" --query "properties.state" -o tsv 2>&1
Write-Host "   Runbook statut : $rbStatus" -ForegroundColor White

Write-Host ""
Write-Host "=== Automation Runbook configure ===" -ForegroundColor Cyan
Write-Host "  Account  : $AA (northeurope)"
Write-Host "  Runbook  : $RB - statut: $rbStatus"
Write-Host "  Schedule : toutes les 15 minutes (start: $startTime)"
Write-Host "  Duree VM : 4h max"
Write-Host ""
$portalUrl = "https://portal.azure.com/" + "#resource/subscriptions/" + $sub + "/resourceGroups/" + $RG + "/providers/Microsoft.Automation/automationAccounts/" + $AA
Write-Host "Portail: $portalUrl" -ForegroundColor Yellow

# Nettoyer les fichiers temp
Remove-Item $rbFile, $schFile -ErrorAction SilentlyContinue
