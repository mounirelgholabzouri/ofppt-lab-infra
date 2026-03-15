$az  = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd"
$SUB = "b64ddf59-d9cf-4c48-8174-27962dfc261c"
$computeRG = "ofppt-lab-formation-tp-d2-0314-1401-210429"
$FQDN = "tp-d2-0314-1401.francecentral.cloudapp.azure.com"

Write-Host "=== Details NIC ===" -ForegroundColor Cyan
$nicRaw = & $az rest --method GET `
    --url "https://management.azure.com/subscriptions/$SUB/resourceGroups/$computeRG/providers/Microsoft.Network/networkInterfaces/tp-d2-0314-1401?api-version=2023-09-01" `
    -o json 2>&1
$nic = $nicRaw | ConvertFrom-Json -ErrorAction SilentlyContinue
Write-Host "NIC NSG: $($nic.properties.networkSecurityGroup)" -ForegroundColor White
$subnetId = $nic.properties.ipConfigurations[0].properties.subnet.id
Write-Host "Subnet ID: $subnetId" -ForegroundColor White
$pip = $nic.properties.ipConfigurations[0].properties.publicIPAddress.id
Write-Host "PIP ID: $pip" -ForegroundColor White

Write-Host ""
Write-Host "=== Details Subnet ===" -ForegroundColor Cyan
if ($subnetId) {
    $subnetRaw = & $az rest --method GET `
        --url "https://management.azure.com$subnetId`?api-version=2023-09-01" `
        -o json 2>&1
    $subnet = $subnetRaw | ConvertFrom-Json -ErrorAction SilentlyContinue
    Write-Host "Subnet NSG: $($subnet.properties.networkSecurityGroup)" -ForegroundColor White
    Write-Host "Address prefix: $($subnet.properties.addressPrefix)" -ForegroundColor White
}

Write-Host ""
Write-Host "=== NSG dans rg-ofppt-devtestlab (VNet RG) ===" -ForegroundColor Cyan
& $az network nsg list --resource-group rg-ofppt-devtestlab --output table 2>&1

Write-Host ""
Write-Host "=== Tous NSG dans l'abonnement ===" -ForegroundColor Cyan
& $az rest --method GET `
    --url "https://management.azure.com/subscriptions/$SUB/providers/Microsoft.Network/networkSecurityGroups?api-version=2023-09-01" `
    --query "value[].{name:name,rg:resourceGroup,location:location}" `
    --output table 2>&1

Write-Host ""
Write-Host "=== Etat VM (OS) ===" -ForegroundColor Cyan
& $az vm get-instance-view `
    --resource-group $computeRG `
    --name tp-d2-0314-1401 `
    --query "instanceView.statuses[].displayStatus" `
    --output table 2>&1

Write-Host ""
Write-Host "=== CustomScript extension details ===" -ForegroundColor Cyan
& $az rest --method GET `
    --url "https://management.azure.com/subscriptions/$SUB/resourceGroups/$computeRG/providers/Microsoft.Compute/virtualMachines/tp-d2-0314-1401/extensions/CustomScript?api-version=2023-07-01" `
    --query "{prov:properties.provisioningState,type:properties.type,settings:properties.settings}" `
    -o json 2>&1
