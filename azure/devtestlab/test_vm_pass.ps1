$az  = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd"
$SUB = "b64ddf59-d9cf-4c48-8174-27962dfc261c"
$RG  = "rg-ofppt-devtestlab"
$LAB = "ofppt-lab-formation"
$vmName = "tp-test-" + (Get-Date -Format "MMdd-HHmm")
$BASE = "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.DevTestLab/labs/$LAB"

Write-Host "Test VM B2s - password correct" -ForegroundColor Cyan
Write-Host "VM: $vmName" -ForegroundColor White

$dtlVnetId = (& $az rest --method GET `
    --url "$BASE/virtualnetworks?api-version=2018-09-15" `
    --query "value[0].id" -o tsv 2>&1).Trim()

# Password Azure-compliant : upper + lower + digit + special
$vmPass = "Ofppt@lab2026!"

$vmBody = @{
    name     = $vmName
    location = "francecentral"
    tags     = @{}
    properties = @{
        size               = "Standard_B2s"
        userName           = "azureofppt"
        password           = $vmPass
        isAuthenticationWithSshKey = $false
        allowClaim         = $false
        disallowPublicIpAddress = $false
        storageType        = "Standard"
        labVirtualNetworkId = $dtlVnetId
        labSubnetName      = "subnet-ofppt-dtl"
        galleryImageReference = @{
            offer     = "ubuntu-22_04-lts"
            publisher = "Canonical"
            sku       = "server-gen1"
            osType    = "Linux"
            version   = "latest"
        }
    }
}
$vmFile = "$env:TEMP\ofppt_vm_pass2.json"
[System.IO.File]::WriteAllText($vmFile, ($vmBody | ConvertTo-Json -Depth 10 -Compress), [System.Text.Encoding]::UTF8)

Write-Host "[1] Creation VM..." -ForegroundColor Green
$r = & $az rest --method PUT `
    --url "$BASE/virtualmachines/${vmName}?api-version=2018-09-15" `
    --body "@$vmFile" `
    --headers "Content-Type=application/json" 2>&1
Remove-Item $vmFile -ErrorAction SilentlyContinue

if (($r -join "") -match "ERROR") {
    Write-Host "ERREUR: $($r | Select-Object -First 3 | ForEach-Object { $_ })" -ForegroundColor Red
    exit 1
}
Write-Host "Creation lancee." -ForegroundColor Green

for ($i = 1; $i -le 10; $i++) {
    Start-Sleep -Seconds 30
    $st = & $az rest --method GET `
        --url "$BASE/virtualmachines/${vmName}?api-version=2018-09-15" `
        --query "{prov:properties.provisioningState,fqdn:properties.fqdn,power:properties.lastKnownPowerState}" `
        -o json 2>&1
    $stObj = $st | ConvertFrom-Json -ErrorAction SilentlyContinue
    Write-Host "  [${i}] prov=$($stObj.prov)  fqdn=$($stObj.fqdn)" -ForegroundColor White
    if ($stObj.prov -eq "Succeeded" -or $stObj.prov -eq "Failed") { break }
}

$stObj = (& $az rest --method GET `
    --url "$BASE/virtualmachines/${vmName}?api-version=2018-09-15" `
    --query "{prov:properties.provisioningState,fqdn:properties.fqdn}" `
    -o json 2>&1) | ConvertFrom-Json -ErrorAction SilentlyContinue

Write-Host ""
if ($stObj.prov -eq "Succeeded" -and $stObj.fqdn) {
    $fqdn = $stObj.fqdn
    Write-Host "VM CREEE AVEC SUCCES !" -ForegroundColor Green
    Write-Host "FQDN  : $fqdn" -ForegroundColor Green
    Write-Host "SSH   : ssh azureofppt@$fqdn" -ForegroundColor Yellow
    Write-Host "Pass  : $vmPass" -ForegroundColor Yellow
    Write-Host "ttyd  : http://${fqdn}:7681" -ForegroundColor Yellow
    $tcp22 = Test-NetConnection -ComputerName $fqdn -Port 22 -WarningAction SilentlyContinue
    Write-Host "Port 22 ouvert: $($tcp22.TcpTestSucceeded)" -ForegroundColor White
} else {
    Write-Host "VM prov=$($stObj.prov)" -ForegroundColor Red
    # Chercher le RG compute pour debug
    $rgsRaw = & $az rest --method GET `
        --url "https://management.azure.com/subscriptions/$SUB/resourcegroups?api-version=2021-04-01" `
        -o json 2>&1
    $rgsObj = $rgsRaw | ConvertFrom-Json -ErrorAction SilentlyContinue
    $cRG = ($rgsObj.value | Where-Object { $_.name -like "*$vmName*" } | Select-Object -First 1).name
    if ($cRG) {
        Write-Host "Ressources RG Compute: $cRG" -ForegroundColor Gray
        & $az resource list --resource-group $cRG --output table 2>&1
    }
}
