$az  = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd"
$SUB = "b64ddf59-d9cf-4c48-8174-27962dfc261c"
$RG_COMPUTE = "ofppt-lab-formation-tp-cloud-0314-1332-650171"
$VM_NAME    = "tp-cloud-0314-1332"

Write-Host "=== Debug VM echec ===" -ForegroundColor Cyan

Write-Host "[1] Statut VM Compute..." -ForegroundColor Green
& $az vm show --resource-group $RG_COMPUTE --name $VM_NAME `
    --query "{prov:provisioningState,powerState:powerState,size:hardwareProfile.vmSize}" `
    --output json 2>&1

Write-Host "[2] Erreur provisioning Compute..." -ForegroundColor Green
& $az vm show --resource-group $RG_COMPUTE --name $VM_NAME `
    --query "provisioningState" --output tsv 2>&1

Write-Host "[3] Ressources dans le RG Compute..." -ForegroundColor Green
& $az resource list --resource-group $RG_COMPUTE --output table 2>&1

Write-Host "[4] Activity log (erreurs)..." -ForegroundColor Green
& $az monitor activity-log list `
    --resource-group $RG_COMPUTE `
    --status Failed `
    --query "[].{op:operationName.value,msg:properties.statusMessage,time:eventTimestamp}" `
    --output table 2>&1

Write-Host "[5] Quotas abonnement..." -ForegroundColor Green
& $az vm list-usage --location francecentral `
    --query "[?contains(name.value,'cores') || contains(name.value,'vCPU')].{name:name.localizedValue,used:currentValue,limit:limit}" `
    --output table 2>&1
