$az  = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd"
$RG  = "rg-ofppt-devtestlab"
$LAB = "ofppt-lab-formation"
$SUB = "b64ddf59-d9cf-4c48-8174-27962dfc261c"
$vmName = "test-vm-" + (Get-Date -Format "MMdd-HHmm")

Write-Host "Attente 20s pour provisioning VNet..." -ForegroundColor Yellow
Start-Sleep -Seconds 20

Write-Host "Statut VNet..." -ForegroundColor Green
& $az rest --method GET `
    --url "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.DevTestLab/labs/$LAB/virtualnetworks/vnet-ofppt-dtl?api-version=2018-09-15" `
    --query "properties.provisioningState" -o tsv 2>&1

$sshKey = (Get-Content "C:\Users\Administrateur\.ssh\ofppt_azure.pub" -Raw).Trim()

Write-Host "Creation VM $vmName..." -ForegroundColor Green
$allOut = & $az lab vm create `
    --lab-name $LAB `
    --resource-group $RG `
    --name $vmName `
    --image "Ubuntu Server 22.04 LTS" `
    --image-type gallery `
    --size Standard_B2s `
    --vnet-name vnet-ofppt-dtl `
    --subnet subnet-ofppt-dtl `
    --authentication-type ssh `
    --ssh-key $sshKey 2>&1

$allOut | ForEach-Object { Write-Host $_ }
Write-Host "Exit: $LASTEXITCODE" -ForegroundColor White

if ($LASTEXITCODE -eq 0) {
    Write-Host "VM creee avec succes!" -ForegroundColor Green
    Start-Sleep -Seconds 30
    & $az lab vm show --lab-name $LAB --resource-group $RG --name $vmName `
        --query "{name:name,state:properties.lastKnownPowerState,prov:properties.provisioningState,fqdn:properties.fqdn}" `
        --output table 2>&1
}
