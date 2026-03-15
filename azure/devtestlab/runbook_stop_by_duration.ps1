<#
.SYNOPSIS
    Arrête automatiquement les VMs Azure DevTest Labs après une durée maximale.

.DESCRIPTION
    Runbook Azure Automation exécuté toutes les 15 minutes.
    Parcourt toutes les VMs du lab, vérifie depuis combien de temps
    chacune tourne, et l'arrête si elle dépasse MAX_DURATION_HOURS.

    Authentification : Managed Identity (System-Assigned) de l'Automation Account.

.PARAMETER ResourceGroupName
    Nom du Resource Group contenant le lab DevTest Labs.

.PARAMETER LabName
    Nom du lab Azure DevTest Labs.

.PARAMETER MaxDurationHours
    Durée maximale de fonctionnement en heures (défaut : 4).

.PARAMETER DryRun
    Si $true, affiche les VMs à arrêter sans les arrêter réellement.

.NOTES
    Auteur  : OFPPT-Lab
    Version : 1.0
    Requis  : Module Az.Accounts, Az.Resources, Az.Monitor
#>

param (
    [string] $ResourceGroupName  = "rg-ofppt-devtestlab",
    [string] $LabName            = "ofppt-lab-formation",
    [int]    $MaxDurationHours   = 4,
    [bool]   $DryRun             = $false
)

# ── Connexion via Managed Identity ────────────────────────────────────────────
Write-Output "=== Runbook OFPPT : Arrêt par durée ==="
Write-Output "Démarré le : $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')"
Write-Output "Lab        : $LabName"
Write-Output "Durée max  : $MaxDurationHours heure(s)"
Write-Output "Mode Dry   : $DryRun"
Write-Output ""

try {
    Connect-AzAccount -Identity -ErrorAction Stop | Out-Null
    Write-Output "[OK] Connecté via Managed Identity"
} catch {
    Write-Error "Impossible de se connecter via Managed Identity : $_"
    throw
}

# ── Récupération des VMs du lab ───────────────────────────────────────────────
Write-Output ""
Write-Output "--- Récupération des VMs du lab '$LabName' ---"

$apiVersion = "2018-09-15"
$subscriptionId = (Get-AzContext).Subscription.Id

try {
    $labVms = Get-AzResource `
        -ResourceGroupName $ResourceGroupName `
        -ResourceType "Microsoft.DevTestLab/labs/virtualmachines" `
        -ResourceName "$LabName/*" `
        -ApiVersion $apiVersion `
        -ErrorAction Stop

    Write-Output "VMs trouvées dans le lab : $($labVms.Count)"
} catch {
    Write-Error "Impossible de lister les VMs du lab : $_"
    throw
}

if ($labVms.Count -eq 0) {
    Write-Output "Aucune VM dans le lab. Runbook terminé."
    exit 0
}

# ── Traitement de chaque VM ───────────────────────────────────────────────────
$now           = Get-Date
$stopped       = 0
$skipped       = 0
$alreadyStopped = 0
$errors        = 0

foreach ($vm in $labVms) {
    $vmName = $vm.Name.Split('/')[-1]
    Write-Output ""
    Write-Output "  ┌─ VM : $vmName"

    # ── Vérifier l'état de la VM ──────────────────────────────────────────────
    try {
        $vmDetail = Get-AzResource `
            -ResourceId "$($vm.ResourceId)" `
            -ApiVersion $apiVersion `
            -ErrorAction Stop

        $powerState = $vmDetail.Properties.computeVm.statuses |
                      Where-Object { $_.code -like "PowerState/*" } |
                      Select-Object -ExpandProperty code -First 1

        Write-Output "  │  État : $powerState"
    } catch {
        Write-Warning "  │  Impossible de lire l'état de $vmName : $_"
        $errors++
        continue
    }

    # Ignorer les VMs déjà arrêtées
    if ($powerState -notlike "*running*") {
        Write-Output "  └─ [IGNORÉE] VM déjà arrêtée"
        $alreadyStopped++
        continue
    }

    # ── Chercher l'heure de démarrage dans le journal d'activité ──────────────
    $startTime = $null
    try {
        $activityLogs = Get-AzActivityLog `
            -ResourceId $vm.ResourceId `
            -StartTime $now.AddHours(-($MaxDurationHours + 2)) `
            -EndTime   $now `
            -ErrorAction SilentlyContinue |
            Where-Object {
                $_.OperationName.Value -like "*start*" -or
                $_.OperationName.Value -like "*Start*"
            } |
            Sort-Object EventTimestamp -Descending |
            Select-Object -First 1

        if ($activityLogs) {
            $startTime = $activityLogs.EventTimestamp
            Write-Output "  │  Démarrée : $($startTime.ToString('dd/MM/yyyy HH:mm:ss'))"
        }
    } catch {
        Write-Warning "  │  Journal d'activité indisponible pour $vmName"
    }

    # Fallback : utiliser la date de création si aucun log de démarrage trouvé
    if (-not $startTime) {
        try {
            $startTime = $vmDetail.Properties.createdDate
            if ($startTime) {
                $startTime = [datetime]$startTime
                Write-Output "  │  Démarrée (date création) : $($startTime.ToString('dd/MM/yyyy HH:mm:ss'))"
            }
        } catch {
            Write-Warning "  │  Impossible de déterminer l'heure de démarrage de $vmName. VM ignorée."
            $skipped++
            continue
        }
    }

    if (-not $startTime) {
        Write-Warning "  └─ [IGNORÉE] Heure de démarrage introuvable"
        $skipped++
        continue
    }

    # ── Calculer la durée de fonctionnement ───────────────────────────────────
    $runningHours   = ($now - $startTime).TotalHours
    $runningMinutes = ($now - $startTime).TotalMinutes

    Write-Output "  │  En fonctionnement depuis : $([math]::Round($runningHours, 1))h ($([math]::Round($runningMinutes)) min)"
    Write-Output "  │  Seuil configuré          : $MaxDurationHours h"

    # ── Décision d'arrêt ──────────────────────────────────────────────────────
    if ($runningHours -ge $MaxDurationHours) {
        if ($DryRun) {
            Write-Output "  └─ [DRY RUN] Serait arrêtée (dépassement de $([math]::Round($runningHours - $MaxDurationHours, 1))h)"
            $stopped++
        } else {
            Write-Output "  │  ⏱ Durée dépassée (+$([math]::Round($runningHours - $MaxDurationHours, 1))h) — Arrêt en cours..."
            try {
                Invoke-AzResourceAction `
                    -ResourceId $vm.ResourceId `
                    -Action "stop" `
                    -ApiVersion $apiVersion `
                    -Force `
                    -ErrorAction Stop | Out-Null

                Write-Output "  └─ [ARRÊTÉE] ✅ VM '$vmName' arrêtée avec succès"
                $stopped++
            } catch {
                Write-Error "  └─ [ERREUR] Impossible d'arrêter '$vmName' : $_"
                $errors++
            }
        }
    } else {
        $remainingMin = [math]::Round(($MaxDurationHours * 60) - $runningMinutes)
        Write-Output "  └─ [OK] Durée respectée — encore ~$remainingMin min disponibles"
        $skipped++
    }
}

# ── Résumé final ──────────────────────────────────────────────────────────────
Write-Output ""
Write-Output "══════════════════════════════════════"
Write-Output "  Résumé du runbook"
Write-Output "──────────────────────────────────────"
Write-Output "  VMs totales        : $($labVms.Count)"
Write-Output "  Déjà arrêtées      : $alreadyStopped"
Write-Output "  Dans la durée limite: $skipped"
Write-Output "  Arrêtées           : $stopped"
Write-Output "  Erreurs            : $errors"
Write-Output "  Mode Dry Run       : $DryRun"
Write-Output "══════════════════════════════════════"
Write-Output "Runbook terminé le : $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')"
