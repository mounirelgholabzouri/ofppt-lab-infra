$az  = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd"
$SUB = "b64ddf59-d9cf-4c48-8174-27962dfc261c"
$VM  = "tp-d2-0314-1401"
$FQDN = "tp-d2-0314-1401.francecentral.cloudapp.azure.com"

Write-Host "=== Test connectivite ports ===" -ForegroundColor Cyan
$tcp22 = Test-NetConnection -ComputerName $FQDN -Port 22 -WarningAction SilentlyContinue
Write-Host "Port 22 (SSH) : $($tcp22.TcpTestSucceeded)" -ForegroundColor $(if ($tcp22.TcpTestSucceeded) { "Green" } else { "Red" })

# Trouver le RG compute
Write-Host ""
Write-Host "=== Recherche RG compute ===" -ForegroundColor Cyan
$rgsRaw = & $az rest --method GET `
    --url "https://management.azure.com/subscriptions/$SUB/resourcegroups?api-version=2021-04-01" `
    -o json 2>&1
$rgsObj = ($rgsRaw | ConvertFrom-Json -ErrorAction SilentlyContinue).value
$computeRG = ($rgsObj | Where-Object { $_.name -like "*$VM*" } | Select-Object -First 1).name
Write-Host "Compute RG: $computeRG" -ForegroundColor White

if (-not $computeRG) {
    Write-Host "RG compute non trouve - cherche avec pattern ofppt-lab-formation" -ForegroundColor Yellow
    $computeRG = ($rgsObj | Where-Object { $_.name -like "*ofppt-lab-formation*" } | Select-Object -First 1).name
    Write-Host "Compute RG (pattern): $computeRG" -ForegroundColor White
}

if ($computeRG) {
    Write-Host ""
    Write-Host "=== Ressources dans $computeRG ===" -ForegroundColor Cyan
    & $az resource list --resource-group $computeRG --output table 2>&1

    Write-Host ""
    Write-Host "=== NSG rules ===" -ForegroundColor Cyan
    $nsgsRaw = & $az rest --method GET `
        --url "https://management.azure.com/subscriptions/$SUB/resourceGroups/$computeRG/providers/Microsoft.Network/networkSecurityGroups?api-version=2023-09-01" `
        -o json 2>&1
    $nsgs = ($nsgsRaw | ConvertFrom-Json -ErrorAction SilentlyContinue).value
    foreach ($nsg in $nsgs) {
        Write-Host "NSG: $($nsg.name)" -ForegroundColor Yellow
        $rules = $nsg.properties.securityRules
        if ($rules) {
            $rules | ForEach-Object {
                Write-Host "  Rule: $($_.name) | Dir: $($_.properties.direction) | Port: $($_.properties.destinationPortRange) | Access: $($_.properties.access)" -ForegroundColor White
            }
        }
        $defaultRules = $nsg.properties.defaultSecurityRules
        Write-Host "  Default rules count: $($defaultRules.Count)" -ForegroundColor Gray
    }

    Write-Host ""
    Write-Host "=== Ajout regle NSG pour port 22 et 7681 ===" -ForegroundColor Cyan
    foreach ($nsg in $nsgs) {
        $nsgName = $nsg.name
        Write-Host "Traitement NSG: $nsgName" -ForegroundColor Yellow

        # Regle SSH port 22
        $rule22Body = @{
            properties = @{
                priority                   = 100
                protocol                   = "Tcp"
                access                     = "Allow"
                direction                  = "Inbound"
                sourceAddressPrefix        = "*"
                sourcePortRange            = "*"
                destinationAddressPrefix   = "*"
                destinationPortRange       = "22"
            }
        }
        $ruleFile22 = "$env:TEMP\rule22.json"
        [System.IO.File]::WriteAllText($ruleFile22, ($rule22Body | ConvertTo-Json -Depth 5 -Compress), [System.Text.Encoding]::UTF8)
        $r22 = & $az rest --method PUT `
            --url "https://management.azure.com/subscriptions/$SUB/resourceGroups/$computeRG/providers/Microsoft.Network/networkSecurityGroups/$nsgName/securityRules/Allow-SSH?api-version=2023-09-01" `
            --body "@$ruleFile22" `
            --headers "Content-Type=application/json" `
            -o json 2>&1
        Remove-Item $ruleFile22 -ErrorAction SilentlyContinue
        if (($r22 -join "") -match '"provisioningState"') {
            Write-Host "  Regle SSH (22) ajoutee/mise a jour" -ForegroundColor Green
        } else {
            Write-Host "  Regle SSH (22) resultat: $($r22 | Select-Object -First 2)" -ForegroundColor Red
        }

        # Regle ttyd port 7681
        $rule7681Body = @{
            properties = @{
                priority                   = 110
                protocol                   = "Tcp"
                access                     = "Allow"
                direction                  = "Inbound"
                sourceAddressPrefix        = "*"
                sourcePortRange            = "*"
                destinationAddressPrefix   = "*"
                destinationPortRange       = "7681"
            }
        }
        $ruleFile7681 = "$env:TEMP\rule7681.json"
        [System.IO.File]::WriteAllText($ruleFile7681, ($rule7681Body | ConvertTo-Json -Depth 5 -Compress), [System.Text.Encoding]::UTF8)
        $r7681 = & $az rest --method PUT `
            --url "https://management.azure.com/subscriptions/$SUB/resourceGroups/$computeRG/providers/Microsoft.Network/networkSecurityGroups/$nsgName/securityRules/Allow-ttyd?api-version=2023-09-01" `
            --body "@$ruleFile7681" `
            --headers "Content-Type=application/json" `
            -o json 2>&1
        Remove-Item $ruleFile7681 -ErrorAction SilentlyContinue
        if (($r7681 -join "") -match '"provisioningState"') {
            Write-Host "  Regle ttyd (7681) ajoutee/mise a jour" -ForegroundColor Green
        } else {
            Write-Host "  Regle ttyd (7681) resultat: $($r7681 | Select-Object -First 2)" -ForegroundColor Red
        }
    }

    Write-Host ""
    Write-Host "Attente propagation NSG (15s)..." -ForegroundColor Gray
    Start-Sleep -Seconds 15

    Write-Host ""
    Write-Host "=== Re-test connectivite ===" -ForegroundColor Cyan
    $tcp22b = Test-NetConnection -ComputerName $FQDN -Port 22 -WarningAction SilentlyContinue
    Write-Host "Port 22 (SSH)  : $($tcp22b.TcpTestSucceeded)" -ForegroundColor $(if ($tcp22b.TcpTestSucceeded) { "Green" } else { "Red" })
    $tcp7681 = Test-NetConnection -ComputerName $FQDN -Port 7681 -WarningAction SilentlyContinue
    Write-Host "Port 7681 (ttyd): $($tcp7681.TcpTestSucceeded)" -ForegroundColor $(if ($tcp7681.TcpTestSucceeded) { "Green" } else { "Red" })
} else {
    Write-Host "Aucun RG compute trouve. VMs dans le lab:" -ForegroundColor Red
    & $az rest --method GET `
        --url "https://management.azure.com/subscriptions/$SUB/resourceGroups/rg-ofppt-devtestlab/providers/Microsoft.DevTestLab/labs/ofppt-lab-formation/virtualmachines?api-version=2018-09-15" `
        --query "value[].{name:name,prov:properties.provisioningState,fqdn:properties.fqdn}" `
        --output table 2>&1
    Write-Host ""
    Write-Host "Tous les RGs:" -ForegroundColor Yellow
    $rgsObj | Select-Object -ExpandProperty name | Sort-Object
}
