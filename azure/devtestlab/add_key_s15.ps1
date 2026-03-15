$az = 'C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd'
$sub = "b64ddf59-d9cf-4c48-8174-27962dfc261c"
$vmName = "tp-s15-test"
$ip = "20.111.9.137"

$rgCompute = & $az group list --subscription $sub `
    --query "[?starts_with(name, 'ofppt-lab-formation-tp-s15')].name" -o tsv 2>&1
$computeId = "/subscriptions/$sub/resourceGroups/$rgCompute/providers/Microsoft.Compute/virtualMachines/$vmName"

$pubKey = (Get-Content "C:\Users\Administrateur\.ssh\ofppt_azure.pub" -Raw).Trim()

$scriptBody = @{
    commandId = "RunShellScript"
    script = @(
        "mkdir -p /home/azureofppt/.ssh",
        "echo '$pubKey' >> /home/azureofppt/.ssh/authorized_keys",
        "chmod 700 /home/azureofppt/.ssh",
        "chmod 600 /home/azureofppt/.ssh/authorized_keys",
        "chown -R azureofppt:azureofppt /home/azureofppt/.ssh",
        "echo 'SSH KEY ADDED'",
        "echo '=== ttyd status ==='",
        "systemctl is-active ttyd && echo 'ttyd: ACTIF' || echo 'ttyd: INACTIF'",
        "ss -tlnp | grep 7681 | head -3"
    )
} | ConvertTo-Json -Depth 3

$scriptFile = "C:\Users\Administrateur\Desktop\ofppt-lab\azure\devtestlab\addkey_cmd.json"
[System.IO.File]::WriteAllText($scriptFile, $scriptBody, [System.Text.Encoding]::UTF8)

Write-Host "Ajout cle SSH + verification ttyd via run-command..."
$result = & $az rest --method POST `
    --url "https://management.azure.com/$computeId/runCommand?api-version=2021-03-01" `
    --headers "Content-Type=application/json" `
    --body "@$scriptFile" 2>&1
Write-Host "Run-command lance (asynchrone)"

# Attendre 20s puis tester SSH
Start-Sleep -Seconds 20
Write-Host ""
Write-Host "=== Test SSH final ==="
$sshResult = ssh -i "C:\Users\Administrateur\.ssh\ofppt_azure" -o StrictHostKeyChecking=no -o ConnectTimeout=15 `
    "azureofppt@$ip" `
    "echo 'SSH OK' && systemctl is-active ttyd && echo 'ttyd: '`$(systemctl is-active ttyd)" 2>&1
Write-Host "SSH: $sshResult"
