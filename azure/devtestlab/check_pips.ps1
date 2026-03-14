$az  = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd"
$SUB = "b64ddf59-d9cf-4c48-8174-27962dfc261c"
Write-Host "Attente 60s..." -ForegroundColor Yellow
Start-Sleep -Seconds 60
Write-Host "PIPs restants..." -ForegroundColor Cyan
& $az rest --method GET `
    --url "https://management.azure.com/subscriptions/$SUB/providers/Microsoft.Network/publicIPAddresses?api-version=2023-09-01" `
    --query "value[].{name:name,rg:resourceGroup,state:properties.provisioningState}" `
    --output table 2>&1
