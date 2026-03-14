$az  = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd"
$sub = (& $az account show --query id -o tsv 2>&1 | Where-Object { $_ -notmatch "WARNING" })[0].Trim()
$RG  = "rg-ofppt-devtestlab"
$AA  = "aa-ofppt-dtl-stop"
$RB  = "StopVmsByDuration"
$SCH = "schedule-stop-4h"
$BASE = "https://management.azure.com/subscriptions/$sub/resourceGroups/$RG/providers/Microsoft.Automation/automationAccounts/$AA"

Write-Host "Subscription : $sub" -ForegroundColor Cyan
Write-Host "Automation Account : $AA" -ForegroundColor Cyan

# Contenu du runbook (version simplifiée inline)
$runbookContent = @'
param (
    [string]$ResourceGroupName = "rg-ofppt-devtestlab",
    [string]$LabName = "ofppt-lab-formation",
    [int]$MaxDurationHours = 4,
    [bool]$DryRun = $false
)
try {
    Connect-AzAccount -Identity | Out-Null
    $vms = Get-AzResource -ResourceGroupName $ResourceGroupName -ResourceType "Microsoft.DevTestLab/labs/virtualmachines"
    $now = Get-Date
    foreach ($vm in $vms) {
        $logs = Get-AzActivityLog -ResourceId $vm.ResourceId -StartTime $now.AddHours(-($MaxDurationHours + 1)) -ErrorAction SilentlyContinue
        $startLog = $logs | Where-Object { $_.OperationName.Value -like "*/start/action" } | Sort-Object EventTimestamp -Descending | Select-Object -First 1
        if ($startLog -and ($now - $startLog.EventTimestamp).TotalHours -ge $MaxDurationHours) {
            Write-Output "[$($vm.Name)] tourne depuis $([math]::Round(($now - $startLog.EventTimestamp).TotalHours,1))h — ARRET"
            if (-not $DryRun) {
                Invoke-AzResourceAction -ResourceId $vm.ResourceId -Action "stop" -ApiVersion "2018-09-15" -Force -ErrorAction SilentlyContinue
            }
        }
    }
} catch { Write-Error $_.Exception.Message }
'@

# ── 1. Créer le runbook via REST API ─────────────────────────────────────────
Write-Host "[1/3] Creation du runbook via REST..." -ForegroundColor Green
$rbBody = @{
    name       = $RB
    location   = "northeurope"
    properties = @{
        runbookType      = "PowerShell"
        logVerbose       = $false
        logProgress      = $false
        description      = "Arret VMs DevTest Labs apres $MaxDurationHours heures"
        publishContentLink = @{
            uri     = ""
            version = "1.0.0.0"
        }
    }
} | ConvertTo-Json -Depth 10

& $az rest --method PUT `
    --url "$BASE/runbooks/${RB}?api-version=2023-11-01" `
    --body $rbBody `
    --output none 2>&1

Write-Host "   Runbook cree" -ForegroundColor Green

# ── 2. Uploader le contenu du runbook (draft) ─────────────────────────────────
Write-Host "[2/3] Upload du contenu du runbook..." -ForegroundColor Green
$contentBody = @{ properties = @{ content = $runbookContent } } | ConvertTo-Json -Depth 5
& $az rest --method PUT `
    --url "$BASE/runbooks/${RB}/draft/content?api-version=2023-11-01" `
    --body $runbookContent `
    --headers "Content-Type=text/powershell" `
    --output none 2>&1

# Publier le runbook
& $az rest --method POST `
    --url "$BASE/runbooks/${RB}/publish?api-version=2023-11-01" `
    --output none 2>&1
Write-Host "   Runbook publie" -ForegroundColor Green

# ── 3. Créer le schedule (toutes les 15 min) ──────────────────────────────────
Write-Host "[3/3] Creation du schedule (15 min)..." -ForegroundColor Green
$startTime = (Get-Date).ToUniversalTime().AddMinutes(10).ToString("yyyy-MM-ddTHH:mm:ssZ")
$schBody = @{
    name       = $SCH
    properties = @{
        startTime   = $startTime
        frequency   = "Minute"
        interval    = 15
        timeZone    = "UTC"
        description = "Arret VMs DTL apres 4h - toutes les 15 min"
    }
} | ConvertTo-Json -Depth 5

& $az rest --method PUT `
    --url "$BASE/schedules/${SCH}?api-version=2023-11-01" `
    --body $schBody `
    --output none 2>&1
Write-Host "   Schedule cree" -ForegroundColor Green

# ── Afficher le résultat ──────────────────────────────────────────────────────
Write-Host ""
Write-Host "=== Runbook Automation configure ===" -ForegroundColor Cyan
Write-Host "  Automation Account : $AA (northeurope)" -ForegroundColor White
Write-Host "  Runbook            : $RB" -ForegroundColor White
Write-Host "  Schedule           : toutes les 15 minutes" -ForegroundColor White
Write-Host "  Duree max VM       : 4 heures" -ForegroundColor White
Write-Host ""
Write-Host "Portail Azure Automation :" -ForegroundColor Yellow
Write-Host "https://portal.azure.com/#resource/subscriptions/$sub/resourceGroups/$RG/providers/Microsoft.Automation/automationAccounts/$AA" -ForegroundColor Yellow
