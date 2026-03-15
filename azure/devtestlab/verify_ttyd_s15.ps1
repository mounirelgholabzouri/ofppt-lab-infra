$az  = 'C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd'
$sub = "b64ddf59-d9cf-4c48-8174-27962dfc261c"
$rg  = "rg-ofppt-devtestlab"
$lab = "ofppt-lab-formation"
$vmName = "tp-s15-test"

# 1. Récupérer IP de la VM
Write-Host "=== Infos VM ==="
$vmData = & $az rest --method GET `
    --url "https://management.azure.com/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.DevTestLab/labs/$lab/virtualmachines/$vmName`?api-version=2018-09-15" 2>&1
$vStr = [string]$vmData
$vidx = $vStr.IndexOf('{')
$vmJson = $vStr.Substring($vidx) | ConvertFrom-Json
$fqdn = $vmJson.properties.fqdn
$computeId = $vmJson.properties.computeId
Write-Host "FQDN: $fqdn"
Write-Host "PowerState: $($vmJson.properties.lastKnownPowerState)"
Write-Host "ArtifactDeploymentStatus: $($vmJson.properties.artifactDeploymentStatus | ConvertTo-Json)"

# 2. Récupérer l'IP publique réelle
$rgCompute = & $az group list --subscription $sub `
    --query "[?starts_with(name, 'ofppt-lab-formation-tp-s15')].name" -o tsv 2>&1
Write-Host "Compute RG: $rgCompute"

$pip = & $az network public-ip list --resource-group $rgCompute `
    --query "[0].ipAddress" -o tsv 2>&1
Write-Host "IP publique: $pip"

# 3. Test SSH + ttyd via run-command
Write-Host ""
Write-Host "=== Test ttyd via run-command Azure ==="
$scriptBody = @{
    commandId = "RunShellScript"
    script = @(
        "echo '=== Test ttyd ===' ",
        "systemctl is-active ttyd 2>/dev/null && echo 'ttyd: ACTIF' || echo 'ttyd: INACTIF'",
        "ss -tlnp | grep 7681 && echo 'Port 7681: OUVERT' || echo 'Port 7681: FERME'",
        "/usr/local/bin/ttyd --version 2>/dev/null | head -1 || echo 'ttyd: non installe'"
    )
} | ConvertTo-Json -Depth 3

$scriptFile = "C:\Users\Administrateur\Desktop\ofppt-lab\azure\devtestlab\ttyd_test_cmd.json"
[System.IO.File]::WriteAllText($scriptFile, $scriptBody, [System.Text.Encoding]::UTF8)

$result = & $az rest --method POST `
    --url "https://management.azure.com/$($computeId)/runCommand?api-version=2021-03-01" `
    --headers "Content-Type=application/json" `
    --body "@$scriptFile" 2>&1

Write-Host $result
