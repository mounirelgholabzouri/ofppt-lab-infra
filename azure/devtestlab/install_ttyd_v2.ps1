$az  = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd"
$SUB = "b64ddf59-d9cf-4c48-8174-27962dfc261c"
$computeRG = "ofppt-lab-formation-tp-d2-0314-1401-210429"
$FQDN = "tp-d2-0314-1401.francecentral.cloudapp.azure.com"

Write-Host "=== Installation ttyd - methode simple ===" -ForegroundColor Cyan

# Etape 1: Telecharger ttyd
Write-Host "[1] Telechargement ttyd..." -ForegroundColor Green
$r1 = & $az vm run-command invoke `
    --resource-group $computeRG `
    --name tp-d2-0314-1401 `
    --command-id RunShellScript `
    --scripts "curl -fsSL https://github.com/tsl0922/ttyd/releases/download/1.7.3/ttyd.x86_64 -o /usr/local/bin/ttyd && chmod +x /usr/local/bin/ttyd && echo TTYD_DOWNLOADED" `
    -o json 2>&1
$jsonIdx = ($r1 -join "").IndexOf('{')
if ($jsonIdx -ge 0) {
    $msg = (($r1 -join "") | Select-String -Pattern '"message"\s*:\s*"([^"]*)"').Matches[0].Groups[1].Value
    Write-Host "Etape 1: $msg" -ForegroundColor White
} else {
    Write-Host ($r1 -join "`n") -ForegroundColor White
}

# Etape 2: Verifier version ttyd
Write-Host "[2] Version ttyd..." -ForegroundColor Green
$r2 = & $az vm run-command invoke `
    --resource-group $computeRG `
    --name tp-d2-0314-1401 `
    --command-id RunShellScript `
    --scripts "/usr/local/bin/ttyd --version 2>&1 || echo NOT_FOUND" `
    -o json 2>&1
$jsonIdx2 = ($r2 -join "").IndexOf('{')
if ($jsonIdx2 -ge 0) {
    $json2 = ($r2 -join "").Substring($jsonIdx2) | ConvertFrom-Json -ErrorAction SilentlyContinue
    Write-Host "ttyd: $($json2.value[0].message)" -ForegroundColor White
}

# Etape 3: Creer service systemd
Write-Host "[3] Creer service systemd..." -ForegroundColor Green
$svcContent = "[Unit]`nDescription=ttyd`nAfter=network.target`n[Service]`nType=simple`nExecStart=/usr/local/bin/ttyd --port 7681 --interface 0.0.0.0 bash`nRestart=always`nUser=azureofppt`n[Install]`nWantedBy=multi-user.target"
$r3 = & $az vm run-command invoke `
    --resource-group $computeRG `
    --name tp-d2-0314-1401 `
    --command-id RunShellScript `
    --scripts "echo '[Unit]' > /etc/systemd/system/ttyd.service && echo 'Description=ttyd' >> /etc/systemd/system/ttyd.service && echo 'After=network.target' >> /etc/systemd/system/ttyd.service && echo '[Service]' >> /etc/systemd/system/ttyd.service && echo 'Type=simple' >> /etc/systemd/system/ttyd.service && echo 'ExecStart=/usr/local/bin/ttyd --port 7681 --interface 0.0.0.0 bash' >> /etc/systemd/system/ttyd.service && echo 'Restart=always' >> /etc/systemd/system/ttyd.service && echo 'User=azureofppt' >> /etc/systemd/system/ttyd.service && echo '[Install]' >> /etc/systemd/system/ttyd.service && echo 'WantedBy=multi-user.target' >> /etc/systemd/system/ttyd.service && systemctl daemon-reload && systemctl enable ttyd && systemctl start ttyd && echo SERVICE_STARTED" `
    -o json 2>&1
$jsonIdx3 = ($r3 -join "").IndexOf('{')
if ($jsonIdx3 -ge 0) {
    $json3 = ($r3 -join "").Substring($jsonIdx3) | ConvertFrom-Json -ErrorAction SilentlyContinue
    Write-Host "Service: $($json3.value[0].message)" -ForegroundColor White
}

# Etape 4: Verifier etat
Write-Host "[4] Verification port 7681..." -ForegroundColor Green
$r4 = & $az vm run-command invoke `
    --resource-group $computeRG `
    --name tp-d2-0314-1401 `
    --command-id RunShellScript `
    --scripts "systemctl status ttyd --no-pager 2>&1; ss -tlnp | grep 7681" `
    -o json 2>&1
$jsonIdx4 = ($r4 -join "").IndexOf('{')
if ($jsonIdx4 -ge 0) {
    $json4 = ($r4 -join "").Substring($jsonIdx4) | ConvertFrom-Json -ErrorAction SilentlyContinue
    Write-Host ($json4.value[0].message) -ForegroundColor White
}

Write-Host ""
Write-Host "=== Test port externe ===" -ForegroundColor Cyan
Start-Sleep -Seconds 5
$tcp7681 = Test-NetConnection -ComputerName $FQDN -Port 7681 -WarningAction SilentlyContinue
Write-Host "Port 7681: $($tcp7681.TcpTestSucceeded)" -ForegroundColor $(if ($tcp7681.TcpTestSucceeded) { "Green" } else { "Red" })
$tcp22 = Test-NetConnection -ComputerName $FQDN -Port 22 -WarningAction SilentlyContinue
Write-Host "Port 22:   $($tcp22.TcpTestSucceeded)" -ForegroundColor $(if ($tcp22.TcpTestSucceeded) { "Green" } else { "Red" })

if ($tcp7681.TcpTestSucceeded) {
    Write-Host ""
    Write-Host "=== SUCCES ! ttyd disponible ===" -ForegroundColor Green
    Write-Host "URL ttyd: http://${FQDN}:7681" -ForegroundColor Yellow
}
