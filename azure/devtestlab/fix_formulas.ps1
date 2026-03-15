$az  = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd"
$SUB = "b64ddf59-d9cf-4c48-8174-27962dfc261c"
$RG  = "rg-ofppt-devtestlab"
$LAB = "ofppt-lab-formation"
$BASE = "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.DevTestLab/labs/$LAB"
$VNET_ID = "/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.Network/virtualNetworks/vnet-ofppt-dtl"
$SUBNET_ID = "$VNET_ID/subnets/subnet-ofppt-dtl"

Write-Host "=== Recreer les formules DTL ===" -ForegroundColor Cyan

# Supprimer les formules en Failed
$formulas = @("OFPPT-Cloud-Computing", "OFPPT-Reseau-Infrastructure", "OFPPT-Cybersecurite")
Write-Host "[1] Suppression formules Failed..." -ForegroundColor Yellow
foreach ($f in $formulas) {
    & $az rest --method DELETE --url "$BASE/formulas/${f}?api-version=2018-09-15" --output none 2>&1
    Write-Host "   Supprimee: $f" -ForegroundColor Gray
}
Start-Sleep -Seconds 5

# Formule de base commune (sans artifacts — source du probleme)
function New-Formula {
    param(
        [string]$Name,
        [string]$Description,
        [string]$Size,
        [int]$DiskGiB
    )
    $body = @{
        name     = $Name
        location = "francecentral"
        properties = @{
            description = $Description
            osType      = "Linux"
            formulaContent = @{
                properties = @{
                    size               = $Size
                    storageType        = "Premium"
                    osDiskSizeGiB      = $DiskGiB
                    disallowPublicIpAddress = $false
                    isAuthenticationWithSshKey = $true
                    labVirtualNetworkId = $VNET_ID
                    labSubnetName       = "subnet-ofppt-dtl"
                    galleryImageReference = @{
                        offer     = "ubuntu-22_04-lts"
                        publisher = "Canonical"
                        sku       = "server-gen1"
                        osType    = "Linux"
                        version   = "latest"
                    }
                }
            }
        }
    }
    $file = "$env:TEMP\ofppt_formula_$Name.json"
    [System.IO.File]::WriteAllText($file, ($body | ConvertTo-Json -Depth 15 -Compress), [System.Text.Encoding]::UTF8)
    $r = & $az rest --method PUT `
        --url "$BASE/formulas/${Name}?api-version=2018-09-15" `
        --body "@$file" `
        --headers "Content-Type=application/json" 2>&1
    Remove-Item $file -ErrorAction SilentlyContinue
    $state = ($r | ConvertFrom-Json -ErrorAction SilentlyContinue).properties.provisioningState
    Write-Host "   $Name : $state" -ForegroundColor White
    return $r
}

Write-Host "[2] Creation formule Cloud Computing..." -ForegroundColor Green
New-Formula -Name "OFPPT-Cloud-Computing" `
    -Description "VM Cloud Computing - Docker, Terraform, kubectl, Azure CLI" `
    -Size "Standard_D4s_v3" `
    -DiskGiB 128

Write-Host "[3] Creation formule Reseau Infrastructure..." -ForegroundColor Green
New-Formula -Name "OFPPT-Reseau-Infrastructure" `
    -Description "VM Reseau - Wireshark, FRRouting, OpenVPN, WireGuard" `
    -Size "Standard_D2s_v3" `
    -DiskGiB 64

Write-Host "[4] Creation formule Cybersecurite..." -ForegroundColor Green
New-Formula -Name "OFPPT-Cybersecurite" `
    -Description "VM Cybersecurite - Metasploit, Nmap, sqlmap, DVWA" `
    -Size "Standard_D4s_v3" `
    -DiskGiB 64

Write-Host ""
Write-Host "[5] Verification finale..." -ForegroundColor Green
Start-Sleep -Seconds 5
& $az lab formula list --lab-name $LAB --resource-group $RG `
    --query "[].{name:name,state:properties.provisioningState}" `
    --output table 2>&1
