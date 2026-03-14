$az  = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd"
$RG  = "rg-ofppt-devtestlab"
$LAB = "ofppt-lab-formation"
$SUB = "b64ddf59-d9cf-4c48-8174-27962dfc261c"
$VNET_NAME = "vnet-ofppt-dtl"
$SUBNET_NAME = "subnet-ofppt-dtl"
$LOCATION = "francecentral"
$BASE = "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.DevTestLab/labs/$LAB"

Write-Host "=== Configuration VNet pour DevTest Lab ===" -ForegroundColor Cyan

# Verifier si VNet existe deja
Write-Host "[1] Verification VNet existant..." -ForegroundColor Green
$vnets = & $az network vnet list --resource-group $RG --output json 2>&1
Write-Host "VNets dans le RG: $vnets" -ForegroundColor Gray

# Creer le VNet
Write-Host "[2] Creation du VNet..." -ForegroundColor Green
& $az network vnet create `
    --name $VNET_NAME `
    --resource-group $RG `
    --location $LOCATION `
    --address-prefix "10.0.0.0/16" `
    --subnet-name $SUBNET_NAME `
    --subnet-prefix "10.0.0.0/24" `
    --output table 2>&1

$vnetId = & $az network vnet show --name $VNET_NAME --resource-group $RG --query id -o tsv 2>&1
$subnetId = & $az network vnet subnet show --name $SUBNET_NAME --vnet-name $VNET_NAME --resource-group $RG --query id -o tsv 2>&1
Write-Host "VNet ID : $vnetId" -ForegroundColor White
Write-Host "Subnet  : $subnetId" -ForegroundColor White

# Associer le VNet au lab via REST
Write-Host "[3] Association VNet au lab..." -ForegroundColor Green
$labVnetBody = @{
    name     = $VNET_NAME
    location = $LOCATION
    properties = @{
        externalProviderResourceId = $vnetId
        description                = "VNet OFPPT DevTest Lab"
        allowedSubnets = @(
            @{
                resourceId     = $subnetId
                labSubnetName  = $SUBNET_NAME
                allowPublicIp  = "Allow"
            }
        )
        subnetOverrides = @(
            @{
                resourceId    = $subnetId
                labSubnetName = $SUBNET_NAME
                useInVmCreationPermission    = "Allow"
                usePublicIpAddressPermission = "Allow"
            }
        )
    }
}
$labVnetFile = "$env:TEMP\ofppt_labnvet.json"
[System.IO.File]::WriteAllText($labVnetFile, ($labVnetBody | ConvertTo-Json -Depth 10 -Compress), [System.Text.Encoding]::UTF8)

$r = & $az rest --method PUT `
    --url "$BASE/virtualnetworks/${VNET_NAME}?api-version=2018-09-15" `
    --body "@$labVnetFile" `
    --headers "Content-Type=application/json" 2>&1
Write-Host "Association: $r" -ForegroundColor White

Remove-Item $labVnetFile -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "VNet $VNET_NAME associe au lab $LAB" -ForegroundColor Cyan
Write-Host "Vous pouvez maintenant creer des VMs" -ForegroundColor Green
