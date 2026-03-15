$az  = 'C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd'
$sub = "b64ddf59-d9cf-4c48-8174-27962dfc261c"
$rg  = "rg-ofppt-devtestlab"
$lab = "ofppt-lab-formation"

# 1. Supprimer tp-s15-test (Failed)
Write-Host "=== Suppression tp-s15-test (Failed) ==="
& $az rest --method DELETE `
    --url "https://management.azure.com/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.DevTestLab/labs/$lab/virtualmachines/tp-s15-test?api-version=2018-09-15" 2>&1
Write-Host "tp-s15-test: DELETE lance"

# 2. Supprimer vm-stagi-cc101t (Running - doit etre supprime depuis session 13)
Write-Host "=== Suppression vm-stagi-cc101t (Running - orphelin session 13) ==="
& $az rest --method DELETE `
    --url "https://management.azure.com/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.DevTestLab/labs/$lab/virtualmachines/vm-stagi-cc101t?api-version=2018-09-15" 2>&1
Write-Host "vm-stagi-cc101t: DELETE lance"

# 3. Deallocate tp-0315-0659 (Stopped - libere les vCPUs)
Write-Host "=== Deallocation tp-0315-0659 (Stopped - liberation vCPUs) ==="
$rgCompute = & $az group list --subscription $sub `
    --query "[?starts_with(name, 'ofppt-lab-formation-tp-0315')].name" -o tsv 2>&1
Write-Host "Compute RG: $rgCompute"
if ($rgCompute) {
    & $az vm deallocate --resource-group $rgCompute --name "tp-0315-0659" --no-wait 2>&1
    Write-Host "tp-0315-0659: DEALLOCATE lance"
}

Write-Host ""
Write-Host "Attente 60s puis verification vCPUs..."
Start-Sleep -Seconds 60

Write-Host "=== Usage vCPUs France Central ==="
& $az vm list-usage --location francecentral --query "[?contains(name.localizedValue, 'Total Regional vCPUs')].{name:name.localizedValue, limit:limit, currentValue:currentValue}" -o table 2>&1
