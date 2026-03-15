$az  = 'C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd'
$sub = "b64ddf59-d9cf-4c48-8174-27962dfc261c"
$vmName = "tp-s15-test"
$ip     = "20.111.9.137"

# Trouver le compute RG
$rgCompute = & $az group list --subscription $sub `
    --query "[?starts_with(name, 'ofppt-lab-formation-tp-s15')].name" -o tsv 2>&1
Write-Host "Compute RG: $rgCompute"

# Créer NSG + rules SSH + ttyd
Write-Host "=== Creation NSG ==="
$nsgName = "nsg-$vmName"
& $az network nsg create --resource-group $rgCompute --name $nsgName --location francecentral 2>&1 | Out-Null
& $az network nsg rule create --resource-group $rgCompute --nsg-name $nsgName --name Allow-SSH `
    --priority 100 --protocol Tcp --destination-port-ranges 22 --access Allow --direction Inbound 2>&1 | Out-Null
& $az network nsg rule create --resource-group $rgCompute --nsg-name $nsgName --name Allow-ttyd `
    --priority 110 --protocol Tcp --destination-port-ranges 7681 --access Allow --direction Inbound 2>&1 | Out-Null
Write-Host "NSG $nsgName cree avec rules SSH+ttyd"

# Attacher NSG a la NIC
$nicName = (& $az network nic list --resource-group $rgCompute --query "[0].name" -o tsv 2>&1)
Write-Host "NIC: $nicName"
& $az network nic update --resource-group $rgCompute --name $nicName `
    --network-security-group $nsgName 2>&1 | Out-Null
Write-Host "NSG attache a la NIC"

# Attendre 15s pour NSG actif
Start-Sleep -Seconds 15

# Test SSH
Write-Host ""
Write-Host "=== Test SSH + ttyd ==="
$sshKey = "C:\Users\Administrateur\.ssh\ofppt_azure"
$sshResult = ssh -i $sshKey -o StrictHostKeyChecking=no -o ConnectTimeout=10 `
    "azureofppt@$ip" `
    "echo 'SSH OK' && systemctl is-active ttyd && ss -tlnp | grep 7681 && echo 'Port 7681 OUVERT'" 2>&1
Write-Host "SSH result: $sshResult"

# Test ttyd port
Write-Host ""
Write-Host "=== Test port 7681 (TCP) ==="
$tcpTest = Test-NetConnection -ComputerName $ip -Port 7681 -WarningAction SilentlyContinue
Write-Host "ttyd port 7681 accessible: $($tcpTest.TcpTestSucceeded)"
