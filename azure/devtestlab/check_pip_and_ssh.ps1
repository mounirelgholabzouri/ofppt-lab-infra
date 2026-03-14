$az  = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd"
$SUB = "b64ddf59-d9cf-4c48-8174-27962dfc261c"
$computeRG = "ofppt-lab-formation-tp-d2-0314-1401-210429"
$FQDN = "tp-d2-0314-1401.francecentral.cloudapp.azure.com"

Write-Host "=== Details PIP ===" -ForegroundColor Cyan
$pipRaw = & $az rest --method GET `
    --url "https://management.azure.com/subscriptions/$SUB/resourceGroups/$computeRG/providers/Microsoft.Network/publicIPAddresses/tp-d2-0314-1401?api-version=2023-09-01" `
    --query "{ip:properties.ipAddress,fqdn:properties.dnsSettings.fqdn,alloc:properties.publicIPAllocationMethod,state:properties.provisioningState}" `
    -o json 2>&1
Write-Host $pipRaw -ForegroundColor White

Write-Host ""
Write-Host "=== Resolution DNS FQDN ===" -ForegroundColor Cyan
Resolve-DnsName $FQDN -ErrorAction SilentlyContinue | Select-Object Name, IPAddress, Type

Write-Host ""
Write-Host "=== Test port 22 par IP directe ===" -ForegroundColor Cyan
$pipObj = ($pipRaw | ConvertFrom-Json -ErrorAction SilentlyContinue)
if ($pipObj.ip) {
    Write-Host "IP: $($pipObj.ip)" -ForegroundColor White
    $tcp22 = Test-NetConnection -ComputerName $pipObj.ip -Port 22 -WarningAction SilentlyContinue
    Write-Host "Port 22 via IP: $($tcp22.TcpTestSucceeded)" -ForegroundColor $(if ($tcp22.TcpTestSucceeded) { "Green" } else { "Red" })

    Write-Host ""
    Write-Host "=== Tentative SSH ===" -ForegroundColor Cyan
    Write-Host "ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no azureofppt@$($pipObj.ip)" -ForegroundColor Yellow
    # On ne peut pas faire SSH interactif, mais on peut tenter un simple test de connexion
    $testConn = & ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o BatchMode=yes azureofppt@$($pipObj.ip) "echo SSH_OK" 2>&1
    Write-Host "SSH result: $testConn" -ForegroundColor White
}

Write-Host ""
Write-Host "=== Test port 7681 (ttyd) ===" -ForegroundColor Cyan
$tcp7681 = Test-NetConnection -ComputerName $FQDN -Port 7681 -WarningAction SilentlyContinue
Write-Host "Port 7681: $($tcp7681.TcpTestSucceeded)" -ForegroundColor $(if ($tcp7681.TcpTestSucceeded) { "Green" } else { "Red" })

Write-Host ""
Write-Host "=== Verifier si ttyd est installe sur la VM ===" -ForegroundColor Cyan
$ttydCheck = & $az vm run-command invoke `
    --resource-group $computeRG `
    --name tp-d2-0314-1401 `
    --command-id RunShellScript `
    --scripts "which ttyd 2>/dev/null && echo 'ttyd found' || echo 'ttyd NOT found'; ps aux | grep ttyd | grep -v grep || echo 'ttyd not running'" `
    -o json 2>&1
$ttydObj = $ttydCheck | Where-Object { $_ -match "message" } | ConvertFrom-Json -ErrorAction SilentlyContinue
if ($ttydObj) {
    Write-Host ($ttydObj.value[0].message) -ForegroundColor White
} else {
    # Extraire le JSON du output mixte
    $jsonPart = ($ttydCheck -join "`n") -replace '^WARNING.*\n', '' -replace '^WARNING[^\n]*\n', ''
    try {
        $ttydObj2 = $jsonPart | ConvertFrom-Json
        Write-Host ($ttydObj2.value[0].message) -ForegroundColor White
    } catch {
        Write-Host ($ttydCheck -join "`n") -ForegroundColor White
    }
}
