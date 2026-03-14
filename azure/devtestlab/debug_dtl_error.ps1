$az  = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd"
$SUB = "b64ddf59-d9cf-4c48-8174-27962dfc261c"
$RG  = "rg-ofppt-devtestlab"
$LAB = "ofppt-lab-formation"
$BASE = "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.DevTestLab/labs/$LAB"

Write-Host "=== Activity log DTL (derniere heure) ===" -ForegroundColor Cyan
$now = (Get-Date).ToUniversalTime()
$start = $now.AddHours(-1).ToString("yyyy-MM-ddTHH:mm:ssZ")

$logsRaw = & $az rest --method GET `
    --url "https://management.azure.com/subscriptions/$SUB/providers/microsoft.insights/eventtypes/management/values?api-version=2015-04-01&`$filter=eventTimestamp ge '$start' and resourceGroupName eq '$RG'" `
    -o json 2>&1
$logs = ($logsRaw | ConvertFrom-Json -ErrorAction SilentlyContinue).value
$errLogs = $logs | Where-Object { $_.level -in @("Error","Critical") -or $_.status.value -eq "Failed" }
if ($errLogs) {
    $errLogs | ForEach-Object {
        Write-Host "TIME : $($_.eventTimestamp)" -ForegroundColor Yellow
        Write-Host "OP   : $($_.operationName.value)" -ForegroundColor White
        Write-Host "MSG  : $($_.properties.statusMessage)" -ForegroundColor Red
        Write-Host "---" -ForegroundColor Gray
    }
} else {
    Write-Host "Aucun log d'erreur dans le RG" -ForegroundColor Gray
    Write-Host "Total logs: $($logs.Count)" -ForegroundColor Gray
}

Write-Host ""
Write-Host "=== Subscription policies ===" -ForegroundColor Cyan
& $az rest --method GET `
    --url "https://management.azure.com/subscriptions/$SUB/providers/Microsoft.Authorization/policyAssignments?api-version=2022-06-01" `
    --query "value[].{name:name,policy:properties.displayName}" `
    --output table 2>&1

Write-Host ""
Write-Host "=== Test creation VM directe via REST API ===" -ForegroundColor Cyan
$sshKey = (Get-Content "C:\Users\Administrateur\.ssh\ofppt_azure.pub" -Raw).Trim()
$RG_TEST = "rg-test-vm-direct"
& $az group create --name $RG_TEST --location francecentral --output none 2>&1
Write-Host "RG cree." -ForegroundColor Green

$vmTestBody = @{
    location = "francecentral"
    properties = @{
        hardwareProfile = @{ vmSize = "Standard_B2s" }
        storageProfile = @{
            imageReference = @{
                publisher = "Canonical"
                offer     = "ubuntu-22_04-lts"
                sku       = "server-gen1"
                version   = "latest"
            }
            osDisk = @{
                createOption = "FromImage"
                managedDisk  = @{ storageAccountType = "Standard_LRS" }
            }
        }
        osProfile = @{
            computerName  = "vm-direct-test"
            adminUsername = "azureofppt"
            adminPassword = "Ofppt@lab2026!"
        }
        networkProfile = @{
            networkInterfaces = @()
        }
    }
}
$testVmFile = "$env:TEMP\test_vm_direct.json"
[System.IO.File]::WriteAllText($testVmFile, ($vmTestBody | ConvertTo-Json -Depth 15 -Compress), [System.Text.Encoding]::UTF8)
$res = & $az rest --method PUT `
    --url "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG_TEST/providers/Microsoft.Compute/virtualMachines/vm-direct-test?api-version=2023-07-01" `
    --body "@$testVmFile" `
    --headers "Content-Type=application/json" 2>&1
Write-Host "Resultat REST VM directe: $($res | Select-Object -First 5 | ForEach-Object { $_ })" -ForegroundColor White
Remove-Item $testVmFile -ErrorAction SilentlyContinue
& $az group delete --name $RG_TEST --yes --no-wait --output none 2>&1
