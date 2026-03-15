param(
    [string]$VmSize    = "Standard_D2s_v3",
    [string]$VmPrefix  = "tp",
    [string]$Formula   = "",
    [switch]$WaitReady
)

# ==============================================================================
# create_vm_with_nsg.ps1 - Creation VM DTL + NSG + ports 22/7681 en une operation
# Usage :
#   .\create_vm_with_nsg.ps1                          # VM D2s_v3 sans formule
#   .\create_vm_with_nsg.ps1 -Formula OFPPT-Cloud-Computing
#   .\create_vm_with_nsg.ps1 -VmSize Standard_D4s_v3 -WaitReady
# ==============================================================================

$az   = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd"
$SUB  = "b64ddf59-d9cf-4c48-8174-27962dfc261c"
$RG   = "rg-ofppt-devtestlab"
$LAB  = "ofppt-lab-formation"
$BASE = "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.DevTestLab/labs/$LAB"

$vmName = "${VmPrefix}-$(Get-Date -Format 'MMdd-HHmm')"
$vmPass = "Ofppt@lab2026!"
$vmUser = "azureofppt"

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host " OFPPT Lab - Creation VM + NSG" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host " VM Name : $vmName" -ForegroundColor White
Write-Host " Size    : $VmSize" -ForegroundColor White
Write-Host " Formula : $(if ($Formula) { $Formula } else { 'aucune (image gallery directe)' })" -ForegroundColor White
Write-Host ""

# -- Etape 1 : Recuperer le VNet DTL -------------------------------------------
Write-Host "[1/5] Recuperation VNet DTL..." -ForegroundColor Green
$dtlVnetId = (& $az rest --method GET `
    --url "$BASE/virtualnetworks?api-version=2018-09-15" `
    --query "value[0].id" -o tsv 2>&1).Trim()

if (-not $dtlVnetId -or $dtlVnetId -match "ERROR") {
    Write-Host "ERREUR: VNet DTL introuvable. Verifiez que setup_vnet.ps1 a ete execute." -ForegroundColor Red
    exit 1
}
Write-Host "VNet DTL : $dtlVnetId" -ForegroundColor Gray

# -- Etape 2 : Creer la VM -----------------------------------------------------
Write-Host "[2/5] Creation VM $vmName ($VmSize)..." -ForegroundColor Green

$vmBody = @{
    name     = $vmName
    location = "francecentral"
    tags     = @{ project = "ofppt-lab"; owner = "dtl-automation" }
    properties = @{
        size                      = $VmSize
        userName                  = $vmUser
        password                  = $vmPass
        isAuthenticationWithSshKey = $false
        allowClaim                = $false
        disallowPublicIpAddress   = $false
        storageType               = "Standard"
        labVirtualNetworkId       = $dtlVnetId
        labSubnetName             = "subnet-ofppt-dtl"
        galleryImageReference     = @{
            offer     = "ubuntu-22_04-lts"
            publisher = "Canonical"
            sku       = "server-gen1"
            osType    = "Linux"
            version   = "latest"
        }
    }
}

# Si formule specifiee, recuperer galleryImageReference + storageType depuis la formule
if ($Formula) {
    Write-Host "Lecture formule $Formula..." -ForegroundColor Gray
    $fRaw = & $az rest --method GET `
        --url "$BASE/formulas/${Formula}?api-version=2018-09-15" `
        -o json 2>&1
    $fJson = ($fRaw -join ""); $fi = $fJson.IndexOf('{')
    $fObj  = if ($fi -ge 0) { $fJson.Substring($fi) | ConvertFrom-Json -ErrorAction SilentlyContinue } else { $null }
    $fGallery = $fObj.properties.formulaContent.properties.galleryImageReference
    if ($fGallery) {
        $vmBody.properties["galleryImageReference"] = $fGallery
        if ($fObj.properties.formulaContent.properties.storageType) {
            $vmBody.properties["storageType"] = $fObj.properties.formulaContent.properties.storageType
        }
        Write-Host "Image formule: $($fGallery.offer) / $($fGallery.sku)" -ForegroundColor Gray
    } else {
        Write-Host "ATTENTION: galleryImageReference non trouve dans formule $Formula - image gallery par defaut utilisee" -ForegroundColor Yellow
    }
}

$vmFile = "$env:TEMP\ofppt_new_vm.json"
[System.IO.File]::WriteAllText($vmFile, ($vmBody | ConvertTo-Json -Depth 10 -Compress), [System.Text.Encoding]::UTF8)

$createRes = & $az rest --method PUT `
    --url "$BASE/virtualmachines/${vmName}?api-version=2018-09-15" `
    --body "@$vmFile" `
    --headers "Content-Type=application/json" 2>&1
Remove-Item $vmFile -ErrorAction SilentlyContinue

if (($createRes -join "") -match '"ERROR"') {
    Write-Host "ERREUR creation VM:" -ForegroundColor Red
    Write-Host ($createRes | Select-Object -First 5 | ForEach-Object { $_ }) -ForegroundColor Red
    exit 1
}
Write-Host "Creation VM lancee." -ForegroundColor Green

# -- Etape 3 : Attendre Succeeded ----------------------------------------------
Write-Host "[3/5] Attente provisioning VM (max 10 min)..." -ForegroundColor Green
$maxTries = 20
$vmProv = ""
$vmFqdn = ""
for ($i = 1; $i -le $maxTries; $i++) {
    Start-Sleep -Seconds 30
    $stRaw = & $az rest --method GET `
        --url "$BASE/virtualmachines/${vmName}?api-version=2018-09-15" `
        --query "{prov:properties.provisioningState,fqdn:properties.fqdn}" `
        -o json 2>&1
    $stJson = ($stRaw -join ""); $si = $stJson.IndexOf('{')
    $stObj  = if ($si -ge 0) { $stJson.Substring($si) | ConvertFrom-Json -ErrorAction SilentlyContinue } else { $null }
    $vmProv = $stObj.prov
    $vmFqdn = $stObj.fqdn
    Write-Host "  [$i/$maxTries] prov=$vmProv  fqdn=$vmFqdn" -ForegroundColor White
    if ($vmProv -eq "Succeeded" -or $vmProv -eq "Failed") { break }
}

if ($vmProv -ne "Succeeded") {
    Write-Host "ECHEC: VM prov=$vmProv" -ForegroundColor Red
    # Recherche RG compute pour debug
    $allRgs = (& $az rest --method GET `
        --url "https://management.azure.com/subscriptions/$SUB/resourcegroups?api-version=2021-04-01" `
        -o json 2>&1 | ConvertFrom-Json -ErrorAction SilentlyContinue).value
    $cRG = ($allRgs | Where-Object { $_.name -like "*$vmName*" } | Select-Object -First 1).name
    if ($cRG) {
        Write-Host "Ressources compute RG ${cRG}:" -ForegroundColor Yellow
        & $az resource list --resource-group $cRG --output table 2>&1
    }
    exit 1
}

Write-Host ""
Write-Host "VM Succeeded: $vmFqdn" -ForegroundColor Green

# -- Etape 4 : Creer NSG + attacher a la NIC -----------------------------------
Write-Host "[4/5] Creation NSG et association NIC..." -ForegroundColor Green

# Trouver le RG compute
$allRgs = (& $az rest --method GET `
    --url "https://management.azure.com/subscriptions/$SUB/resourcegroups?api-version=2021-04-01" `
    -o json 2>&1 | ConvertFrom-Json -ErrorAction SilentlyContinue).value
$computeRG = ($allRgs | Where-Object { $_.name -like "*$vmName*" } | Select-Object -First 1).name

if (-not $computeRG) {
    Write-Host "ATTENTION: RG compute non trouve pour $vmName - NSG non cree" -ForegroundColor Yellow
} else {
    Write-Host "Compute RG: $computeRG" -ForegroundColor Gray
    $NSG_NAME = "nsg-$vmName"

    # Creer NSG avec regles SSH + ttyd + HTTP
    $nsgBody = @{
        location = "francecentral"
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
    $nsgFile = "$env:TEMP\nsg_new.json"
    [System.IO.File]::WriteAllText($nsgFile, ($nsgBody | ConvertTo-Json -Depth 10 -Compress), [System.Text.Encoding]::UTF8)
    $nsgRes = & $az rest --method PUT `
        --url "https://management.azure.com/subscriptions/$SUB/resourceGroups/$computeRG/providers/Microsoft.Network/networkSecurityGroups/${NSG_NAME}?api-version=2023-09-01" `
        --body "@$nsgFile" `
        --headers "Content-Type=application/json" `
        -o json 2>&1
    Remove-Item $nsgFile -ErrorAction SilentlyContinue
    $nsgObj = ($nsgRes -join "") | ConvertFrom-Json -ErrorAction SilentlyContinue
    $NSG_ID = $nsgObj.id

    if ($NSG_ID) {
        Write-Host "NSG cree: $NSG_NAME" -ForegroundColor Gray
        Start-Sleep -Seconds 10

        # Attacher NSG a la NIC
        $nicRes = & $az network nic update `
            --resource-group $computeRG `
            --name $vmName `
            --network-security-group $NSG_ID `
            --output none 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "NSG attache a la NIC" -ForegroundColor Green
        } else {
            Write-Host "ATTENTION: echec attachement NSG: $nicRes" -ForegroundColor Yellow
        }
    } else {
        Write-Host "ATTENTION: echec creation NSG" -ForegroundColor Yellow
    }
}

# -- Etape 5 : Verifier connectivite -------------------------------------------
Write-Host "[5/5] Test connectivite..." -ForegroundColor Green
Start-Sleep -Seconds 15

$tcp22 = Test-NetConnection -ComputerName $vmFqdn -Port 22 -WarningAction SilentlyContinue
$tcp7681 = Test-NetConnection -ComputerName $vmFqdn -Port 7681 -WarningAction SilentlyContinue

# -- Rapport final -------------------------------------------------------------
Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host " VM CREEE AVEC SUCCES !" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host " Nom      : $vmName" -ForegroundColor White
Write-Host " FQDN     : $vmFqdn" -ForegroundColor White
Write-Host " SSH      : ssh ${vmUser}@${vmFqdn}" -ForegroundColor Yellow
Write-Host " Password : $vmPass" -ForegroundColor Yellow
Write-Host " ttyd     : http://${vmFqdn}:7681" -ForegroundColor Yellow
Write-Host " Port 22  : $($tcp22.TcpTestSucceeded)" -ForegroundColor $(if ($tcp22.TcpTestSucceeded) { "Green" } else { "Red" })
Write-Host " Port 7681: $($tcp7681.TcpTestSucceeded)" -ForegroundColor $(if ($tcp7681.TcpTestSucceeded) { "Green" } else { "Yellow" })
Write-Host ""

if (-not $tcp7681.TcpTestSucceeded) {
    Write-Host "Note: Port 7681 non ouvert - ttyd sera disponible apres execution" -ForegroundColor Yellow
    Write-Host "      de l artifact cloud-tools (via formule DTL), ou manuellement:" -ForegroundColor Yellow
    Write-Host "      powershell -File install_ttyd_v2.ps1" -ForegroundColor Gray
}
