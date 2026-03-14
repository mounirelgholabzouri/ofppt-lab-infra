$az   = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd"
$sub  = "b64ddf59-d9cf-4c48-8174-27962dfc261c"
$RG   = "rg-ofppt-devtestlab"
$AA   = "aa-ofppt-dtl-stop"
$RB   = "StopVmsByDuration"
$SCH  = "schedule-stop-4h"
$BASE = "https://management.azure.com/subscriptions/$sub/resourceGroups/$RG/providers/Microsoft.Automation/automationAccounts/$AA"

Write-Host "=== Creation schedule + job schedule ===" -ForegroundColor Cyan

# Utiliser demain a minuit UTC comme start time (clairement dans le futur)
$tomorrow = (Get-Date).ToUniversalTime().Date.AddDays(1).ToString("yyyy-MM-ddT00:30:00+00:00")
Write-Host "Start time: $tomorrow" -ForegroundColor Cyan

$schBody = @{
    name     = $SCH
    properties = @{
        startTime   = $tomorrow
        frequency   = "Hour"
        interval    = 1
        timeZone    = "UTC"
        description = "Arret VMs DTL apres 4h - toutes heures"
    }
}
$schJson = $schBody | ConvertTo-Json -Depth 5 -Compress
$schFile = "$env:TEMP\ofppt_sch2.json"
Write-Host "JSON body: $schJson" -ForegroundColor Gray
[System.IO.File]::WriteAllText($schFile, $schJson, [System.Text.Encoding]::UTF8)

# Essai avec API version 2022-08-08
Write-Host "Tentative avec api-version 2022-08-08..." -ForegroundColor Yellow
$r1 = & $az rest --method PUT `
    --url "$BASE/schedules/${SCH}?api-version=2022-08-08" `
    --body "@$schFile" `
    --headers "Content-Type=application/json" 2>&1
Write-Host "Resultat: $r1" -ForegroundColor White

if ($r1 -match '"name"') {
    Write-Host "Schedule cree avec succes!" -ForegroundColor Green

    # Lier runbook au schedule (job schedule)
    $jsId = [System.Guid]::NewGuid().ToString()
    $jsBody = @{
        properties = @{
            schedule = @{ name = $SCH }
            runbook  = @{ name = $RB }
            parameters = @{
                ResourceGroupName = "rg-ofppt-devtestlab"
                LabName           = "ofppt-lab-formation"
                MaxDurationHours  = "4"
                DryRun            = "false"
            }
        }
    }
    $jsFile = "$env:TEMP\ofppt_js2.json"
    [System.IO.File]::WriteAllText($jsFile, ($jsBody | ConvertTo-Json -Depth 10 -Compress), [System.Text.Encoding]::UTF8)

    Write-Host "Liaison runbook <-> schedule..." -ForegroundColor Green
    $r2 = & $az rest --method PUT `
        --url "$BASE/jobSchedules/${jsId}?api-version=2022-08-08" `
        --body "@$jsFile" `
        --headers "Content-Type=application/json" 2>&1
    Write-Host "Job schedule: $r2" -ForegroundColor White
    Remove-Item $jsFile -ErrorAction SilentlyContinue
} else {
    Write-Host "ECHEC - schedule non cree" -ForegroundColor Red
}

Remove-Item $schFile -ErrorAction SilentlyContinue
Write-Host ""
Write-Host "Runbook '$RB' est Published et pret." -ForegroundColor Cyan
Write-Host "Configurez le schedule manuellement via le portail si necessaire." -ForegroundColor Yellow
