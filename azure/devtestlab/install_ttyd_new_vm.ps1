# install_ttyd_new_vm.ps1 — Installe ttyd sur la VM recree vm-admin-cc101t
$az        = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd"
$computeRG = "ofppt-lab-formation-vm-admin-cc101t-017751"
$vmName    = "vm-admin-cc101t"

Write-Host "=== Installation ttyd sur $vmName ===" -ForegroundColor Cyan

function RunCmd($rg, $vm, $script) {
    $r = & $az vm run-command invoke `
        --resource-group $rg --name $vm `
        --command-id RunShellScript `
        --scripts $script -o json 2>&1
    $idx = ($r -join "").IndexOf("{")
    if ($idx -ge 0) {
        $json = ($r -join "").Substring($idx) | ConvertFrom-Json -ErrorAction SilentlyContinue
        return $json.value[0].message
    }
    return ($r -join "`n")
}

# Etape 1: ttyd est deja installe — verifier
Write-Host "[1] Verification ttyd..." -ForegroundColor Green
$v = RunCmd $computeRG $vmName "/usr/local/bin/ttyd --version 2>&1 || echo NOT_FOUND"
Write-Host "  $v"

# Etape 2: Creer le service systemd
Write-Host "[2] Creation service systemd..." -ForegroundColor Green
$svc = @"
echo '[Unit]' > /etc/systemd/system/ttyd.service
echo 'Description=ttyd Web Terminal' >> /etc/systemd/system/ttyd.service
echo 'After=network.target' >> /etc/systemd/system/ttyd.service
echo '[Service]' >> /etc/systemd/system/ttyd.service
echo 'Type=simple' >> /etc/systemd/system/ttyd.service
echo 'ExecStart=/usr/local/bin/ttyd --port 7681 --interface 0.0.0.0 bash' >> /etc/systemd/system/ttyd.service
echo 'Restart=always' >> /etc/systemd/system/ttyd.service
echo 'User=azureofppt' >> /etc/systemd/system/ttyd.service
echo '[Install]' >> /etc/systemd/system/ttyd.service
echo 'WantedBy=multi-user.target' >> /etc/systemd/system/ttyd.service
systemctl daemon-reload && systemctl enable ttyd && systemctl start ttyd && echo SVC_STARTED
"@
$svcOneLine = $svc -replace "`n", " && " -replace "\s+&&\s+", " && "
$msg2 = RunCmd $computeRG $vmName $svcOneLine
Write-Host "  $msg2"

# Etape 3: Verifier etat
Write-Host "[3] Verification port 7681..." -ForegroundColor Green
$msg3 = RunCmd $computeRG $vmName "systemctl is-active ttyd 2>&1; ss -tlnp | grep 7681 || echo PORT_NOT_LISTENING"
Write-Host "  $msg3"

# Etape 4: NSG — verifier/creer regles
Write-Host "[4] Verification NSG..." -ForegroundColor Green
$nsgList = & $az network nsg list --resource-group $computeRG --query "[].name" -o tsv 2>&1
Write-Host "  NSGs: $nsgList"

Write-Host ""
Write-Host "=== Termine ===" -ForegroundColor Green
Write-Host "  ttyd URL : http://vm-admin-cc101t.francecentral.cloudapp.azure.com:7681"
