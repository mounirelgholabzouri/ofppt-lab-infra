$az = 'C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd'
Write-Host "=== VMs DTL ==="
& $az rest --method GET `
    --url "https://management.azure.com/subscriptions/b64ddf59-d9cf-4c48-8174-27962dfc261c/resourceGroups/rg-ofppt-devtestlab/providers/Microsoft.DevTestLab/labs/ofppt-lab-formation/virtualmachines?api-version=2018-09-15" `
    --query "value[].{name:name,state:properties.lastKnownPowerState,status:properties.provisioningState}" -o table 2>&1
