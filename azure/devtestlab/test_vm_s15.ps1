$az  = 'C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd'
$sub = "b64ddf59-d9cf-4c48-8174-27962dfc261c"
$rg  = "rg-ofppt-devtestlab"
$lab = "ofppt-lab-formation"
$vmName = "tp-s15-test"

Write-Host "=== Creation VM test session 15 ==="
Write-Host "Heure debut: $(Get-Date -Format 'HH:mm:ss')"

# GET DTL VNet ID (scoped)
$vnets = & $az rest --method GET `
    --url "https://management.azure.com/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.DevTestLab/labs/$lab/virtualnetworks?api-version=2018-09-15" 2>&1
$vnetsStr = [string]$vnets
$idx = $vnetsStr.IndexOf('{')
$vnetsJson = $vnetsStr.Substring($idx) | ConvertFrom-Json
$vnetId    = $vnetsJson.value[0].id
$subnetName = $vnetsJson.value[0].properties.allowedSubnets[0].labSubnetName
Write-Host "DTL VNet ID: $vnetId"
Write-Host "Subnet: $subnetName"

# GET formule image reference
$formulaData = & $az rest --method GET `
    --url "https://management.azure.com/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.DevTestLab/labs/$lab/formulas/OFPPT-Cloud-Computing?api-version=2018-09-15" 2>&1
$fStr = [string]$formulaData
$fidx = $fStr.IndexOf('{')
$fc = ($fStr.Substring($fidx) | ConvertFrom-Json).properties.formulaContent.properties
$imageRef = $fc.galleryImageReference
Write-Host "Image: $($imageRef.offer) $($imageRef.sku)"

$ttydArtifactId = "/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.DevTestLab/labs/$lab/artifactsources/ofppt-lab-infra/artifacts/ttyd-install"

$body = @{
    location = "francecentral"
    properties = @{
        labVirtualNetworkId     = $vnetId
        labSubnetName           = $subnetName
        size                    = "Standard_D2s_v3"
        userName                = "azureofppt"
        password                = "Ofppt@lab2026!"
        storageType             = "Standard"
        allowClaim              = $false
        disallowPublicIpAddress = $false
        galleryImageReference   = $imageRef
        artifacts = @(
            @{
                artifactId = $ttydArtifactId
                parameters = @(
                    @{ name = "ttydPort"; value = "7681" }
                    @{ name = "ttydUser"; value = "azureofppt" }
                )
            }
        )
    }
} | ConvertTo-Json -Depth 15

$bodyFile = "C:\Users\Administrateur\Desktop\ofppt-lab\azure\devtestlab\vm_s15_body.json"
[System.IO.File]::WriteAllText($bodyFile, $body, [System.Text.Encoding]::UTF8)

Write-Host "Lancement creation VM $vmName..."
$result = & $az rest --method PUT `
    --url "https://management.azure.com/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.DevTestLab/labs/$lab/virtualmachines/$vmName`?api-version=2018-09-15" `
    --headers "Content-Type=application/json" `
    --body "@$bodyFile" 2>&1

$rStr = [string]$result
if ($rStr -match "provisioningState") {
    $ridx = $rStr.IndexOf('{')
    $rjson = $rStr.Substring($ridx) | ConvertFrom-Json
    Write-Host "provisioningState: $($rjson.properties.provisioningState)"
    Write-Host "OK - VM creation lancee"
} else {
    Write-Host "ERREUR: $rStr"
}
