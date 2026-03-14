$az  = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd"
$RG  = "rg-ofppt-devtestlab"
$LAB = "ofppt-lab-formation"
$SUB = "b64ddf59-d9cf-4c48-8174-27962dfc261c"

Write-Host "Gallery images disponibles dans le lab..." -ForegroundColor Cyan
& $az lab gallery-image list --lab-name $LAB --resource-group $RG --output table 2>&1

Write-Host ""
Write-Host "Base images marketplace (via REST)..." -ForegroundColor Cyan
& $az rest --method GET `
    --url "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.DevTestLab/labs/$LAB/galleryImages?api-version=2018-09-15" `
    --query "value[].{name:name,publisher:properties.imageReference.publisher,offer:properties.imageReference.offer,sku:properties.imageReference.sku}" `
    --output table 2>&1
