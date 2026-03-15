$az = 'C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd'
$sub = "b64ddf59-d9cf-4c48-8174-27962dfc261c"
$rg  = "rg-ofppt-devtestlab"
$lab = "ofppt-lab-formation"
Write-Host "Suppression VM de test tp-s15-test..."
& $az rest --method DELETE `
    --url "https://management.azure.com/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.DevTestLab/labs/$lab/virtualmachines/tp-s15-test?api-version=2018-09-15" 2>&1
Write-Host "tp-s15-test: DELETE lance"
