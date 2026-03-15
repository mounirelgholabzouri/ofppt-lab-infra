$az  = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd"
$SUB = "b64ddf59-d9cf-4c48-8174-27962dfc261c"
$computeRG = "ofppt-lab-formation-tp-d2-0314-1401-210429"
$VM = "tp-d2-0314-1401"

Write-Host "=== Diagnostic SSH via az vm run-command ===" -ForegroundColor Cyan
Write-Host "Execution commandes sur la VM (sans SSH)..." -ForegroundColor Yellow

$result = & $az vm run-command invoke `
    --resource-group $computeRG `
    --name $VM `
    --command-id RunShellScript `
    --scripts "systemctl status ssh --no-pager; echo '---'; ufw status; echo '---'; ss -tlnp | grep ':22'; echo '---'; cat /etc/ssh/sshd_config | grep -E '^(Port|ListenAddress|PermitRootLogin|PasswordAuthentication|PubkeyAuthentication)'" `
    -o json 2>&1

$res = $result | ConvertFrom-Json -ErrorAction SilentlyContinue
if ($res.value) {
    $res.value | ForEach-Object {
        Write-Host "=== $($_.code) ===" -ForegroundColor Yellow
        Write-Host $_.message -ForegroundColor White
    }
} else {
    Write-Host "Resultat brut:" -ForegroundColor Red
    Write-Host ($result -join "`n") -ForegroundColor White
}
