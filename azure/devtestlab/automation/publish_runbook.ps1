$az   = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd"
$sub  = "b64ddf59-d9cf-4c48-8174-27962dfc261c"
$RG   = "rg-ofppt-devtestlab"
$AA   = "aa-ofppt-dtl-stop"
$RB   = "StopVmsByDuration"
$SCH  = "schedule-stop-4h"
$BASE = "https://management.azure.com/subscriptions/$sub/resourceGroups/$RG/providers/Microsoft.Automation/automationAccounts/$AA"

Write-Host "=== Publication runbook + schedule ===" -ForegroundColor Cyan

# 1. Contenu du runbook
$runbookContent = @'
param (
    [string]$ResourceGroupName = "rg-ofppt-devtestlab",
    [string]$LabName           = "ofppt-lab-formation",
    [int]$MaxDurationHours     = 4,
    [bool]$DryRun              = $false
)
try {
    Connect-AzAccount -Identity | Out-Null
    $vms = Get-AzResource -ResourceGroupName $ResourceGroupName -ResourceType "Microsoft.DevTestLab/labs/virtualmachines"
    $now = Get-Date
    foreach ($vm in $vms) {
        $logs = Get-AzActivityLog -ResourceId $vm.ResourceId -StartTime $now.AddHours(-($MaxDurationHours + 1)) -ErrorAction SilentlyContinue
        $startLog = $logs | Where-Object { $_.OperationName.Value -like "*/start/action" } | Sort-Object EventTimestamp -Descending | Select-Object -First 1
        if ($startLog -and ($now - $startLog.EventTimestamp).TotalHours -ge $MaxDurationHours) {
            Write-Output "[$($vm.Name)] tourne depuis $([math]::Round(($now - $startLog.EventTimestamp).TotalHours,1))h - ARRET"
            if (-not $DryRun) {
                Invoke-AzResourceAction -ResourceId $vm.ResourceId -Action "stop" -ApiVersion "2018-09-15" -Force -ErrorAction SilentlyContinue
            }
        }
    }
} catch { Write-Error $_.Exception.Message }
'@

# 2. Upload le contenu (draft)
Write-Host "[1/4] Upload contenu runbook (draft)..." -ForegroundColor Green
$draftFile = "$env:TEMP\ofppt_rb_content.ps1"
[System.IO.File]::WriteAllText($draftFile, $runbookContent, [System.Text.Encoding]::UTF8)
& $az rest --method PUT `
    --url "$BASE/runbooks/${RB}/draft/content?api-version=2023-11-01" `
    --body "@$draftFile" `
    --headers "Content-Type=text/powershell" `
    --output none 2>&1
Write-Host "   Draft uploaded" -ForegroundColor Green

# 3. Publier le runbook
Write-Host "[2/4] Publication du runbook..." -ForegroundColor Green
& $az rest --method POST `
    --url "$BASE/runbooks/${RB}/publish?api-version=2023-11-01" `
    --headers "Content-Type=application/json" `
    --output none 2>&1
Start-Sleep -Seconds 5
$rbStatus = & $az rest --method GET --url "$BASE/runbooks/${RB}?api-version=2023-11-01" --query "properties.state" -o tsv 2>&1
Write-Host "   Runbook statut: $rbStatus" -ForegroundColor White

# 4. Creer le schedule (20 min offset)
Write-Host "[3/4] Creation schedule 15min (start +20min)..." -ForegroundColor Green
$startTime = (Get-Date).ToUniversalTime().AddMinutes(20).ToString("yyyy-MM-ddTHH:mm:ssZ")
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
$schFile = "$env:TEMP\ofppt_sch.json"
[System.IO.File]::WriteAllText($schFile, ($schBody | ConvertTo-Json -Depth 5 -Compress), [System.Text.Encoding]::UTF8)
& $az rest --method PUT `
    --url "$BASE/schedules/${SCH}?api-version=2023-11-01" `
    --body "@$schFile" `
    --headers "Content-Type=application/json" `
    --output none 2>&1
Write-Host "   Schedule cree (start: $startTime)" -ForegroundColor Green

# 5. Lier runbook au schedule (job schedule)
Write-Host "[4/4] Liaison runbook <-> schedule..." -ForegroundColor Green
$jsName = "js-" + $RB + "-" + $SCH
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
$jsFile = "$env:TEMP\ofppt_js.json"
[System.IO.File]::WriteAllText($jsFile, ($jsBody | ConvertTo-Json -Depth 10 -Compress), [System.Text.Encoding]::UTF8)
& $az rest --method PUT `
    --url "$BASE/jobSchedules/${jsName}?api-version=2023-11-01" `
    --body "@$jsFile" `
    --headers "Content-Type=application/json" 2>&1

Write-Host ""
Write-Host "=== Runbook Automation PRET ===" -ForegroundColor Cyan
Write-Host "  Runbook  : $RB ($rbStatus)" -ForegroundColor White
Write-Host "  Schedule : toutes les 15 min (depuis $startTime)" -ForegroundColor White
Write-Host "  Arret    : VMs > 4h sont stoppees" -ForegroundColor White
$portalUrl = "https://portal.azure.com/" + "#resource/subscriptions/" + $sub + "/resourceGroups/" + $RG + "/providers/Microsoft.Automation/automationAccounts/" + $AA
Write-Host "  Portail  : $portalUrl" -ForegroundColor Yellow

Remove-Item $draftFile, $schFile, $jsFile -ErrorAction SilentlyContinue
