$az  = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd"
$SUB = "b64ddf59-d9cf-4c48-8174-27962dfc261c"
$computeRG = "ofppt-lab-formation-tp-d2-0314-1401-210429"
$FQDN = "tp-d2-0314-1401.francecentral.cloudapp.azure.com"

Write-Host "=== Installation ttyd sur la VM ===" -ForegroundColor Cyan
Write-Host "Execution via az vm run-command (peut prendre 1-2 min)..." -ForegroundColor Yellow

$installScript = @'
#!/bin/bash
set -e
echo "[1] Mise a jour apt..."
apt-get update -qq

echo "[2] Installation dependances ttyd..."
apt-get install -y -qq libwebsockets-dev libjson-c-dev cmake build-essential > /dev/null 2>&1 || true

echo "[3] Telechargement ttyd binaire..."
TTYD_VERSION="1.7.3"
TTYD_URL="https://github.com/tsl0922/ttyd/releases/download/${TTYD_VERSION}/ttyd.x86_64"
curl -sL "$TTYD_URL" -o /usr/local/bin/ttyd
chmod +x /usr/local/bin/ttyd

echo "[4] Verification ttyd..."
ttyd --version 2>&1 || /usr/local/bin/ttyd --version 2>&1

echo "[5] Creation service systemd ttyd..."
cat > /etc/systemd/system/ttyd.service << 'SVCEOF'
[Unit]
Description=ttyd - Terminal in browser
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/ttyd --port 7681 --interface 0.0.0.0 bash
Restart=always
RestartSec=5
User=azureofppt
Environment=HOME=/home/azureofppt

[Install]
WantedBy=multi-user.target
SVCEOF

echo "[6] Demarrage service ttyd..."
systemctl daemon-reload
systemctl enable ttyd
systemctl start ttyd
systemctl status ttyd --no-pager

echo "[7] Port 7681 ecoute:"
ss -tlnp | grep 7681 || echo "Port 7681 non ecoute"
echo "INSTALLATION TERMINEE"
'@

$result = & $az vm run-command invoke `
    --resource-group $computeRG `
    --name tp-d2-0314-1401 `
    --command-id RunShellScript `
    --scripts "$installScript" `
    -o json 2>&1

# Extraire le message (WARNING peut preceder le JSON)
$jsonStart = ($result -join "`n").IndexOf('{')
if ($jsonStart -ge 0) {
    $jsonStr = ($result -join "`n").Substring($jsonStart)
    try {
        $resObj = $jsonStr | ConvertFrom-Json
        Write-Host ($resObj.value[0].message) -ForegroundColor White
    } catch {
        Write-Host ($result -join "`n") -ForegroundColor White
    }
} else {
    Write-Host ($result -join "`n") -ForegroundColor White
}

Write-Host ""
Write-Host "=== Test port 7681 ===" -ForegroundColor Cyan
Start-Sleep -Seconds 5
$tcp7681 = Test-NetConnection -ComputerName $FQDN -Port 7681 -WarningAction SilentlyContinue
Write-Host "Port 7681 (ttyd): $($tcp7681.TcpTestSucceeded)" -ForegroundColor $(if ($tcp7681.TcpTestSucceeded) { "Green" } else { "Red" })

if ($tcp7681.TcpTestSucceeded) {
    Write-Host ""
    Write-Host "=== ttyd accessible ! ===" -ForegroundColor Green
    Write-Host "URL: http://${FQDN}:7681" -ForegroundColor Yellow
}
