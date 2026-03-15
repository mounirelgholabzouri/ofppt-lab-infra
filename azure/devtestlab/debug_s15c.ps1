$az  = 'C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd'
$sub = "b64ddf59-d9cf-4c48-8174-27962dfc261c"
$rg  = "rg-ofppt-devtestlab"

Write-Host "=== PIPs alloues ==="
& $az network public-ip list --subscription $sub --query "[].{name:name,rg:resourceGroup,state:provisioningState,ip:ipAddress}" -o table 2>&1

Write-Host ""
Write-Host "=== Activity Log tp-s15-test (10 dernieres minutes) ==="
$filter = "eventTimestamp ge '$(([DateTime]::UtcNow).AddMinutes(-10).ToString('yyyy-MM-ddTHH:mm:ssZ'))'"
$logs = & $az rest --method GET `
    --url "https://management.azure.com/subscriptions/$sub/providers/Microsoft.Insights/eventtypes/management/values?api-version=2015-04-01&`$filter=$filter" 2>&1
$lStr = [string]$logs
$lidx = $lStr.IndexOf('{')
if ($lidx -ge 0) {
    $ljson = $lStr.Substring($lidx) | ConvertFrom-Json
    $ljson.value | Where-Object { $_.status.value -eq "Failed" -or $_.status.value -eq "failed" } | Select-Object -First 5 | ForEach-Object {
        Write-Host "Op: $($_.operationName.localizedValue)"
        Write-Host "Status: $($_.status.value)"
        $msg = $_.properties.statusMessage
        if ($msg.Length -gt 300) { $msg = $msg.Substring(0, 300) + "..." }
        Write-Host "Msg: $msg"
        Write-Host "---"
    }
}
