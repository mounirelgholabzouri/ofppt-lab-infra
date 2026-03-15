$az  = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd"
$SUB = "b64ddf59-d9cf-4c48-8174-27962dfc261c"
$RG  = "rg-ofppt-devtestlab"
$LAB = "ofppt-lab-formation"
$vmName = "tp-cloud-" + (Get-Date -Format "MMdd-HHmm")
$BASE = "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.DevTestLab/labs/$LAB"

Write-Host "Test VM Ubuntu 22.04 via REST" -ForegroundColor Cyan
Write-Host "VM: $vmName" -ForegroundColor White

# Recuperer le vrai ID DTL du VNet (format Microsoft.DevTestLab)
Write-Host "[0] Recuperation ID DTL du VNet..." -ForegroundColor Green
$labVnetRaw = & $az rest --method GET `
    --url "$BASE/virtualnetworks?api-version=2018-09-15" `
    --query "value[0]" --output json 2>&1
$labVnet = $labVnetRaw | ConvertFrom-Json -ErrorAction SilentlyContinue
$dtlVnetId = $labVnet.id
$subnetName = ($labVnet.properties.subnetOverrides | Select-Object -First 1).labSubnetName
Write-Host "DTL VNet ID : $dtlVnetId" -ForegroundColor White
Write-Host "Subnet name : $subnetName" -ForegroundColor White

$sshKey = (Get-Content "C:\Users\Administrateur\.ssh\ofppt_azure.pub" -Raw).Trim()

$vmBody = @{
    name     = $vmName
    location = "francecentral"
    tags     = @{}
    properties = @{
        size               = "Standard_B2s"
        userName           = "azureofppt"
        isAuthenticationWithSshKey = $true
        sshKey             = $sshKey
        allowClaim         = $false
        disallowPublicIpAddress = $false
        storageType        = "Standard"
        labVirtualNetworkId = $dtlVnetId
        labSubnetName      = $subnetName
        galleryImageReference = @{
            offer     = "ubuntu-22_04-lts"
            publisher = "Canonical"
            sku       = "server-gen1"
            osType    = "Linux"
            version   = "latest"
        }
    }
}
$vmFile = "$env:TEMP\ofppt_vm3.json"
[System.IO.File]::WriteAllText($vmFile, ($vmBody | ConvertTo-Json -Depth 10 -Compress), [System.Text.Encoding]::UTF8)

Write-Host "[1] Creation VM..." -ForegroundColor Green
$r = & $az rest --method PUT `
    --url "$BASE/virtualmachines/${vmName}?api-version=2018-09-15" `
    --body "@$vmFile" `
    --headers "Content-Type=application/json" 2>&1
$r | Select-Object -First 5 | ForEach-Object { Write-Host $_ }
Remove-Item $vmFile -ErrorAction SilentlyContinue

if (($r -join "") -match "ERROR") {
    Write-Host "Echec creation VM." -ForegroundColor Red
    exit 1
}
Write-Host "Creation lancee." -ForegroundColor Green

Write-Host "[2] Attente 90s..." -ForegroundColor Yellow
Start-Sleep -Seconds 90

Write-Host "[3] Statut VM..." -ForegroundColor Green
$rawSt = & $az rest --method GET `
    --url "$BASE/virtualmachines/${vmName}?api-version=2018-09-15" 2>&1
$vmSt = ($rawSt | Where-Object { $_ -match "^{" }) | ConvertFrom-Json -ErrorAction SilentlyContinue
if ($vmSt) {
    $prov  = $vmSt.properties.provisioningState
    $fqdn  = $vmSt.properties.fqdn
    $power = $vmSt.properties.lastKnownPowerState
    Write-Host "Prov : $prov  Power: $power" -ForegroundColor White
    Write-Host "FQDN : $fqdn" -ForegroundColor White
    if ($fqdn) {
        Write-Host "SSH  : ssh -i C:\Users\Administrateur\.ssh\ofppt_azure azureofppt@$fqdn" -ForegroundColor Yellow
        Write-Host "ttyd : http://${fqdn}:7681" -ForegroundColor Yellow
        $tcp = Test-NetConnection -ComputerName $fqdn -Port 22 -WarningAction SilentlyContinue
        Write-Host "Port22: $($tcp.TcpTestSucceeded)" -ForegroundColor White
    }
} else {
    Write-Host "Reponse: $rawSt" -ForegroundColor Gray
}

Write-Host "[4] Toutes les VMs..." -ForegroundColor Green
& $az rest --method GET `
    --url "$BASE/virtualmachines?api-version=2018-09-15" `
    --query "value[].{name:name,prov:properties.provisioningState,power:properties.lastKnownPowerState,fqdn:properties.fqdn}" `
    --output table 2>&1
