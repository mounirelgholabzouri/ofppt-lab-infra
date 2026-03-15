$az  = 'C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd'
$sub = "b64ddf59-d9cf-4c48-8174-27962dfc261c"
$rg  = "rg-ofppt-devtestlab"
$lab = "ofppt-lab-formation"
$vmName = "tp-s15-test"

Write-Host "=== Detail VM Failed ==="
$result = & $az rest --method GET `
    --url "https://management.azure.com/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.DevTestLab/labs/$lab/virtualmachines/$vmName`?api-version=2018-09-15" 2>&1
$rStr = [string]$result
$ridx = $rStr.IndexOf('{')
$json = $rStr.Substring($ridx) | ConvertFrom-Json
Write-Host "provisioningState : $($json.properties.provisioningState)"
Write-Host "artifactDeploymentStatus:"
$json.properties.artifactDeploymentStatus | ConvertTo-Json -Depth 5
Write-Host ""
Write-Host "artifacts results:"
$json.properties.artifacts | ConvertTo-Json -Depth 10
