$az  = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd"
$SUB = "b64ddf59-d9cf-4c48-8174-27962dfc261c"
$RG  = "rg-ofppt-devtestlab"
$LAB = "ofppt-lab-formation"
$vmName = "tp-cloud-0314-1332"
$BASE = "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.DevTestLab/labs/$LAB"

Write-Host "Attente VM $vmName..." -ForegroundColor Cyan

$maxWait = 20
for ($i = 1; $i -le $maxWait; $i++) {
    $raw = & $az rest --method GET `
        --url "$BASE/virtualmachines/${vmName}?api-version=2018-09-15" `
        --output json 2>&1
    $vmSt = ($raw | ConvertFrom-Json -ErrorAction SilentlyContinue)
    $prov  = $vmSt.properties.provisioningState
    $fqdn  = $vmSt.properties.fqdn
    $power = $vmSt.properties.lastKnownPowerState
    Write-Host "  [$i/$maxWait] Prov=$prov  Power=$power  FQDN=$fqdn" -ForegroundColor White
    if ($prov -eq "Succeeded" -or $prov -eq "Failed") { break }
    Start-Sleep -Seconds 30
}

Write-Host ""
if ($vmSt.properties.provisioningState -eq "Succeeded") {
    $fqdn = $vmSt.properties.fqdn
    Write-Host "VM PRETE !" -ForegroundColor Green
    Write-Host "FQDN : $fqdn" -ForegroundColor Green
    Write-Host "SSH  : ssh -i C:\Users\Administrateur\.ssh\ofppt_azure azureofppt@$fqdn" -ForegroundColor Yellow
    Write-Host "ttyd : http://${fqdn}:7681" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Test port 22..." -ForegroundColor Green
    $tcp = Test-NetConnection -ComputerName $fqdn -Port 22 -WarningAction SilentlyContinue
    Write-Host "Port 22 accessible: $($tcp.TcpTestSucceeded)" -ForegroundColor White
    Write-Host "Test port 7681 (ttyd)..." -ForegroundColor Green
    $tcp7681 = Test-NetConnection -ComputerName $fqdn -Port 7681 -WarningAction SilentlyContinue
    Write-Host "Port 7681 accessible: $($tcp7681.TcpTestSucceeded)" -ForegroundColor White
} else {
    Write-Host "VM en etat: $($vmSt.properties.provisioningState)" -ForegroundColor Red
    Write-Host $raw -ForegroundColor Gray
}
