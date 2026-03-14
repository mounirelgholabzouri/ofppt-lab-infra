$az  = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd"
$SUB = "b64ddf59-d9cf-4c48-8174-27962dfc261c"

Write-Host "=== Tailles B-series disponibles en FranceCentral ===" -ForegroundColor Cyan
& $az vm list-skus --location francecentral --size Standard_B --all `
    --query "[?restrictions[0].reasonCode != 'NotAvailableForSubscription' && !restrictions].{size:name,cpu:capabilities[?name=='vCPUs'].value|[0],ram:capabilities[?name=='MemoryGB'].value|[0]}" `
    --output table 2>&1

Write-Host ""
Write-Host "=== Tailles D-series v3/v4/v5 disponibles ===" -ForegroundColor Cyan
& $az vm list-skus --location francecentral --size Standard_D2 --all `
    --query "[?!restrictions].{size:name}" `
    --output table 2>&1

Write-Host ""
Write-Host "=== Tailles autorisees par la policy DTL ===" -ForegroundColor Yellow
Write-Host "Standard_B2s, Standard_B4ms, Standard_D2s_v3, Standard_D4s_v3" -ForegroundColor White
