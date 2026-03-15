$az  = 'C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd'
$sub = "b64ddf59-d9cf-4c48-8174-27962dfc261c"
$rg  = "rg-ofppt-devtestlab"
$lab = "ofppt-lab-formation"
$vmName = "tp-s15-test"

Write-Host "=== Activity Log DTL VM ==="
$filter = "eventTimestamp ge '$(([DateTime]::UtcNow).AddMinutes(-30).ToString('yyyy-MM-ddTHH:mm:ssZ'))' and resourceGroupName eq '$rg'"
$logs = & $az rest --method GET `
    --url "https://management.azure.com/subscriptions/$sub/providers/Microsoft.Insights/eventtypes/management/values?api-version=2015-04-01&`$filter=$filter&`$select=status,operationName,properties" 2>&1
$lStr = [string]$logs
$lidx = $lStr.IndexOf('{')
if ($lidx -ge 0) {
    $ljson = $lStr.Substring($lidx) | ConvertFrom-Json
    $errors = $ljson.value | Where-Object { $_.status.value -eq "Failed" }
    if ($errors) {
        foreach ($e in $errors) {
            Write-Host "Operation: $($e.operationName.localizedValue)"
            Write-Host "Status: $($e.status.value)"
            Write-Host "Message: $($e.properties.statusMessage)"
            Write-Host "---"
        }
    } else {
        Write-Host "Pas d'erreurs dans les 30 dernieres minutes"
        # Montrer toutes les operations
        $ljson.value | Select-Object -First 10 | ForEach-Object {
            Write-Host "$($_.status.value) | $($_.operationName.localizedValue)"
        }
    }
}
