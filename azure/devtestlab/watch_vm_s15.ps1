$az  = 'C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd'
$sub = "b64ddf59-d9cf-4c48-8174-27962dfc261c"
$rg  = "rg-ofppt-devtestlab"
$lab = "ofppt-lab-formation"
$vmName = "tp-s15-test"
$maxWait = 1200
$elapsed = 0

Write-Host "Surveillance VM $vmName (max ${maxWait}s)..."
while ($elapsed -lt $maxWait) {
    Start-Sleep -Seconds 30
    $elapsed += 30
    $result = & $az rest --method GET `
        --url "https://management.azure.com/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.DevTestLab/labs/$lab/virtualmachines/$vmName`?api-version=2018-09-15" 2>&1
    $rStr = [string]$result
    $ridx = $rStr.IndexOf('{')
    if ($ridx -ge 0) {
        $json = $rStr.Substring($ridx) | ConvertFrom-Json
        $prov  = $json.properties.provisioningState
        $power = $json.properties.lastKnownPowerState
        $ip    = $json.properties.computeId
        Write-Host "[${elapsed}s] provisioningState=$prov | powerState=$power"
        if ($prov -eq "Succeeded") {
            Write-Host "VM SUCCEEDED apres ${elapsed}s !"
            # Recup IP publique
            $fqdn = $json.properties.fqdn
            Write-Host "FQDN: $fqdn"
            break
        } elseif ($prov -eq "Failed") {
            Write-Host "VM FAILED - verifier les logs DTL"
            break
        }
    } else {
        Write-Host "[${elapsed}s] En attente..."
    }
}
