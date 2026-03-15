$az  = 'C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd'
$sub = "b64ddf59-d9cf-4c48-8174-27962dfc261c"
$rg  = "rg-ofppt-devtestlab"
$lab = "ofppt-lab-formation"
$vmName = "tp-s15-test"

# Attendre liberation vCPUs
Write-Host "Attente liberation vCPUs..."
$maxWait = 180
$elapsed = 0
while ($elapsed -lt $maxWait) {
    Start-Sleep -Seconds 30
    $elapsed += 30
    $usage = & $az vm list-usage --location francecentral `
        --query "[?contains(name.localizedValue, 'Total Regional vCPUs')].currentValue" -o tsv 2>&1
    Write-Host "[${elapsed}s] vCPUs utilises: $usage / 4"
    if ([int]$usage -le 0) {
        Write-Host "vCPUs liberes!"
        break
    }
}

Write-Host ""
Write-Host "=== Re-creation VM tp-s15-test ==="
Write-Host "Heure: $(Get-Date -Format 'HH:mm:ss')"

# GET DTL VNet
$vnets = & $az rest --method GET `
    --url "https://management.azure.com/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.DevTestLab/labs/$lab/virtualnetworks?api-version=2018-09-15" 2>&1
$vStr = [string]$vnets
$vidx = $vStr.IndexOf('{')
$vJson = $vStr.Substring($vidx) | ConvertFrom-Json
$vnetId = $vJson.value[0].id
$subnetName = $vJson.value[0].properties.allowedSubnets[0].labSubnetName

# GET image depuis formule
$fData = & $az rest --method GET `
    --url "https://management.azure.com/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.DevTestLab/labs/$lab/formulas/OFPPT-Cloud-Computing?api-version=2018-09-15" 2>&1
$fStr = [string]$fData
$fidx = $fStr.IndexOf('{')
$imageRef = ($fStr.Substring($fidx) | ConvertFrom-Json).properties.formulaContent.properties.galleryImageReference

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

$bodyFile = "C:\Users\Administrateur\Desktop\ofppt-lab\azure\devtestlab\vm_s15_body2.json"
[System.IO.File]::WriteAllText($bodyFile, $body, [System.Text.Encoding]::UTF8)

$result = & $az rest --method PUT `
    --url "https://management.azure.com/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.DevTestLab/labs/$lab/virtualmachines/$vmName`?api-version=2018-09-15" `
    --headers "Content-Type=application/json" `
    --body "@$bodyFile" 2>&1

$rStr = [string]$result
if ($rStr -match "provisioningState") {
    $ridx = $rStr.IndexOf('{')
    $rjson = $rStr.Substring($ridx) | ConvertFrom-Json
    Write-Host "provisioningState: $($rjson.properties.provisioningState)"
    Write-Host "VM creation lancee avec succes"
} else {
    Write-Host "ERREUR: $rStr"
}
