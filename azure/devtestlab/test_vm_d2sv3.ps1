$az  = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd"
$SUB = "b64ddf59-d9cf-4c48-8174-27962dfc261c"
$RG  = "rg-ofppt-devtestlab"
$LAB = "ofppt-lab-formation"
$vmName = "tp-d2-" + (Get-Date -Format "MMdd-HHmm")
$BASE = "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.DevTestLab/labs/$LAB"

Write-Host "Test VM Standard_D2s_v3" -ForegroundColor Cyan
Write-Host "VM: $vmName" -ForegroundColor White

# Nettoyage VMs Failed existantes + PIPs
Write-Host "[0] Nettoyage VMs Failed..." -ForegroundColor Yellow
$vmsRaw = & $az rest --method GET `
    --url "$BASE/virtualmachines?api-version=2018-09-15" `
    --query "value[?properties.provisioningState=='Failed'].name" -o tsv 2>&1
$vmsRaw | ForEach-Object {
    $vmn = $_.Trim()
    if ($vmn) {
        & $az rest --method DELETE --url "$BASE/virtualmachines/${vmn}?api-version=2018-09-15" --output none 2>&1 | Out-Null
        Write-Host "   Supprimee: $vmn" -ForegroundColor Gray
    }
}
Write-Host "   Attente 15s propagation..." -ForegroundColor Gray
Start-Sleep -Seconds 15

$dtlVnetId = (& $az rest --method GET `
    --url "$BASE/virtualnetworks?api-version=2018-09-15" `
    --query "value[0].id" -o tsv 2>&1).Trim()

$vmBody = @{
    name     = $vmName
    location = "francecentral"
    tags     = @{}
    properties = @{
        size               = "Standard_D2s_v3"
        userName           = "azureofppt"
        password           = "Ofppt@lab2026!"
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
$vmFile = "$env:TEMP\ofppt_vm_d2sv3.json"
[System.IO.File]::WriteAllText($vmFile, ($vmBody | ConvertTo-Json -Depth 10 -Compress), [System.Text.Encoding]::UTF8)

Write-Host "[1] Creation VM D2s_v3..." -ForegroundColor Green
$r = & $az rest --method PUT `
    --url "$BASE/virtualmachines/${vmName}?api-version=2018-09-15" `
    --body "@$vmFile" `
    --headers "Content-Type=application/json" 2>&1
Remove-Item $vmFile -ErrorAction SilentlyContinue

if (($r -join "") -match '"ERROR"') {
    Write-Host "ERREUR: $($r | Select-Object -First 3)" -ForegroundColor Red
    exit 1
}
Write-Host "Creation lancee." -ForegroundColor Green

for ($i = 1; $i -le 10; $i++) {
    Start-Sleep -Seconds 30
    $stObj = & $az rest --method GET `
        --url "$BASE/virtualmachines/${vmName}?api-version=2018-09-15" `
        --query "{prov:properties.provisioningState,fqdn:properties.fqdn}" `
        -o json 2>&1 | ConvertFrom-Json -ErrorAction SilentlyContinue
    Write-Host "  [${i}] prov=$($stObj.prov)  fqdn=$($stObj.fqdn)" -ForegroundColor White
    if ($stObj.prov -eq "Succeeded" -or $stObj.prov -eq "Failed") { break }
}

$final = & $az rest --method GET `
    --url "$BASE/virtualmachines/${vmName}?api-version=2018-09-15" `
    --query "{prov:properties.provisioningState,fqdn:properties.fqdn}" `
    -o json 2>&1 | ConvertFrom-Json -ErrorAction SilentlyContinue

Write-Host ""
if ($final.prov -eq "Succeeded" -and $final.fqdn) {
    $fqdn = $final.fqdn
    Write-Host "VM CREEE AVEC SUCCES !" -ForegroundColor Green
    Write-Host "FQDN  : $fqdn" -ForegroundColor Green
    Write-Host "SSH   : ssh azureofppt@$fqdn  (pass: Ofppt@lab2026!)" -ForegroundColor Yellow
    Write-Host "ttyd  : http://${fqdn}:7681" -ForegroundColor Yellow
    $tcp22 = Test-NetConnection -ComputerName $fqdn -Port 22 -WarningAction SilentlyContinue
    Write-Host "Port 22 : $($tcp22.TcpTestSucceeded)" -ForegroundColor White
} else {
    Write-Host "VM prov=$($final.prov) - verifier taille disponible." -ForegroundColor Red
    Write-Host "Si encore SkuNotAvailable, mettre a jour la policy DTL." -ForegroundColor Yellow
}
