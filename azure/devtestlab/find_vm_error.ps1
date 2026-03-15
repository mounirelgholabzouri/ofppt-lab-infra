$az  = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd"
$SUB = "b64ddf59-d9cf-4c48-8174-27962dfc261c"
$COMPUTE_RG = "ofppt-lab-formation-tp-test-0314-1337-036212"

Write-Host "=== Ressources dans RG Compute ===" -ForegroundColor Cyan
& $az resource list --resource-group $COMPUTE_RG --output table 2>&1

Write-Host ""
Write-Host "=== Deployments ARM dans le RG Compute ===" -ForegroundColor Cyan
& $az deployment group list --resource-group $COMPUTE_RG --output table 2>&1

Write-Host ""
Write-Host "=== Erreur du dernier deployment ===" -ForegroundColor Cyan
$deployName = & $az deployment group list --resource-group $COMPUTE_RG --query "[0].name" -o tsv 2>&1
if ($deployName -and $deployName -notmatch "ERROR") {
    & $az deployment group show --resource-group $COMPUTE_RG --name $deployName.Trim() `
        --query "properties.error" --output json 2>&1
}
