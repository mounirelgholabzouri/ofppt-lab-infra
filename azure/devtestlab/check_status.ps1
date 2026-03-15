$az = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd"
$SUB = "b64ddf59-d9cf-4c48-8174-27962dfc261c"
$RG  = "rg-ofppt-devtestlab"
$AA  = "aa-ofppt-dtl-stop"
$LAB = "ofppt-lab-formation"

Write-Host "--- RESOURCES ---" -ForegroundColor Cyan
& $az resource list --resource-group $RG --output table 2>&1

Write-Host "--- RUNBOOK ---" -ForegroundColor Cyan
& $az rest --method GET --url "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.Automation/automationAccounts/$AA/runbooks/StopVmsByDuration?api-version=2022-08-08" --query "{state:properties.state,type:properties.runbookType}" --output json 2>&1

Write-Host "--- SCHEDULE ---" -ForegroundColor Cyan
& $az rest --method GET --url "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.Automation/automationAccounts/$AA/schedules/schedule-stop-4h?api-version=2022-08-08" --query "{enabled:properties.isEnabled,freq:properties.frequency,next:properties.nextRun}" --output json 2>&1

Write-Host "--- VNETS LAB ---" -ForegroundColor Cyan
& $az rest --method GET --url "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.DevTestLab/labs/$LAB/virtualnetworks?api-version=2018-09-15" --query "value[].{name:name,state:properties.provisioningState}" --output table 2>&1

Write-Host "--- FORMULES ---" -ForegroundColor Cyan
& $az lab formula list --lab-name $LAB --resource-group $RG --query "[].{name:name,state:properties.provisioningState}" --output table 2>&1
