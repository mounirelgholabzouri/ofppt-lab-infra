$az  = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd"
$SUB = "b64ddf59-d9cf-4c48-8174-27962dfc261c"
$computeRG = "ofppt-lab-formation-tp-d2-0314-1401-210429"
$FQDN = "tp-d2-0314-1401.francecentral.cloudapp.azure.com"
$LOCATION = "francecentral"
$NSG_NAME = "nsg-tp-d2-0314-1401"

Write-Host "=== Creation NSG pour la VM DTL ===" -ForegroundColor Cyan

# 1. Creer le NSG
Write-Host "[1] Creation NSG $NSG_NAME..." -ForegroundColor Green
$nsgBody = @{
    location = $LOCATION
    properties = @{
        securityRules = @(
            @{
                name = "Allow-SSH"
                properties = @{
                    priority                 = 100
                    protocol                 = "Tcp"
                    access                   = "Allow"
                    direction                = "Inbound"
                    sourceAddressPrefix      = "*"
                    sourcePortRange          = "*"
                    destinationAddressPrefix = "*"
                    destinationPortRange     = "22"
                }
            },
            @{
                name = "Allow-ttyd"
                properties = @{
                    priority                 = 110
                    protocol                 = "Tcp"
                    access                   = "Allow"
                    direction                = "Inbound"
                    sourceAddressPrefix      = "*"
                    sourcePortRange          = "*"
                    destinationAddressPrefix = "*"
                    destinationPortRange     = "7681"
                }
            },
            @{
                name = "Allow-HTTP"
                properties = @{
                    priority                 = 120
                    protocol                 = "Tcp"
                    access                   = "Allow"
                    direction                = "Inbound"
                    sourceAddressPrefix      = "*"
                    sourcePortRange          = "*"
                    destinationAddressPrefix = "*"
                    destinationPortRange     = "80"
                }
            }
        )
    }
}
$nsgFile = "$env:TEMP\nsg_body.json"
[System.IO.File]::WriteAllText($nsgFile, ($nsgBody | ConvertTo-Json -Depth 10 -Compress), [System.Text.Encoding]::UTF8)
$nsgRes = & $az rest --method PUT `
    --url "https://management.azure.com/subscriptions/$SUB/resourceGroups/$computeRG/providers/Microsoft.Network/networkSecurityGroups/${NSG_NAME}?api-version=2023-09-01" `
    --body "@$nsgFile" `
    --headers "Content-Type=application/json" `
    -o json 2>&1
Remove-Item $nsgFile -ErrorAction SilentlyContinue

$nsgObj = $nsgRes | ConvertFrom-Json -ErrorAction SilentlyContinue
if ($nsgObj.id) {
    Write-Host "NSG cree: $($nsgObj.id)" -ForegroundColor Green
    $NSG_ID = $nsgObj.id
} else {
    Write-Host "Erreur creation NSG:" -ForegroundColor Red
    Write-Host ($nsgRes -join "`n") -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "[2] Attente provisioning NSG (10s)..." -ForegroundColor Gray
Start-Sleep -Seconds 10

# 2. Lire la NIC actuelle pour recuperer sa config complete
Write-Host "[3] Lecture NIC actuelle..." -ForegroundColor Green
$nicRaw = & $az rest --method GET `
    --url "https://management.azure.com/subscriptions/$SUB/resourceGroups/$computeRG/providers/Microsoft.Network/networkInterfaces/tp-d2-0314-1401?api-version=2023-09-01" `
    -o json 2>&1
$nicObj = $nicRaw | ConvertFrom-Json -ErrorAction SilentlyContinue

if (-not $nicObj.id) {
    Write-Host "Erreur lecture NIC:" -ForegroundColor Red
    Write-Host ($nicRaw -join "`n") -ForegroundColor Red
    exit 1
}

# 3. Associer NSG a la NIC
Write-Host "[4] Association NSG a la NIC..." -ForegroundColor Green
$nicObj.properties.networkSecurityGroup = @{ id = $NSG_ID }

# Supprimer les proprietes read-only avant PUT
if ($nicObj.properties.PSObject.Properties["provisioningState"]) {
    $nicObj.properties.PSObject.Properties.Remove("provisioningState")
}
if ($nicObj.properties.PSObject.Properties["resourceGuid"]) {
    $nicObj.properties.PSObject.Properties.Remove("resourceGuid")
}
if ($nicObj.properties.PSObject.Properties["macAddress"]) {
    $nicObj.properties.PSObject.Properties.Remove("macAddress")
}
if ($nicObj.properties.PSObject.Properties["primary"]) {
    $nicObj.properties.PSObject.Properties.Remove("primary")
}
if ($nicObj.properties.PSObject.Properties["vnetEncryptionSupported"]) {
    $nicObj.properties.PSObject.Properties.Remove("vnetEncryptionSupported")
}

$nicFile = "$env:TEMP\nic_update.json"
[System.IO.File]::WriteAllText($nicFile, ($nicObj | ConvertTo-Json -Depth 20 -Compress), [System.Text.Encoding]::UTF8)
$nicUpdateRes = & $az rest --method PUT `
    --url "https://management.azure.com/subscriptions/$SUB/resourceGroups/$computeRG/providers/Microsoft.Network/networkInterfaces/tp-d2-0314-1401?api-version=2023-09-01" `
    --body "@$nicFile" `
    --headers "Content-Type=application/json" `
    -o json 2>&1
Remove-Item $nicFile -ErrorAction SilentlyContinue

$nicUpdateObj = $nicUpdateRes | ConvertFrom-Json -ErrorAction SilentlyContinue
if ($nicUpdateObj.id) {
    Write-Host "NIC mise a jour avec NSG" -ForegroundColor Green
} else {
    Write-Host "Erreur mise a jour NIC:" -ForegroundColor Red
    Write-Host ($nicUpdateRes | Select-Object -First 5 | ForEach-Object { $_ }) -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "[5] Attente propagation (20s)..." -ForegroundColor Gray
Start-Sleep -Seconds 20

Write-Host ""
Write-Host "=== Test final connectivite ===" -ForegroundColor Cyan
$tcp22 = Test-NetConnection -ComputerName $FQDN -Port 22 -WarningAction SilentlyContinue
Write-Host "Port 22 (SSH)  : $($tcp22.TcpTestSucceeded)" -ForegroundColor $(if ($tcp22.TcpTestSucceeded) { "Green" } else { "Red" })
$tcp7681 = Test-NetConnection -ComputerName $FQDN -Port 7681 -WarningAction SilentlyContinue
Write-Host "Port 7681 (ttyd): $($tcp7681.TcpTestSucceeded)" -ForegroundColor $(if ($tcp7681.TcpTestSucceeded) { "Green" } else { "Red" })

if ($tcp22.TcpTestSucceeded) {
    Write-Host ""
    Write-Host "=== SSH accessible ! ===" -ForegroundColor Green
    Write-Host "ssh azureofppt@$FQDN" -ForegroundColor Yellow
    Write-Host "Password: Ofppt@lab2026!" -ForegroundColor Yellow
}
