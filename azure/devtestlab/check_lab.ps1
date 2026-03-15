$az = 'C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd'

Write-Host "=== LAB ==="
& $az lab show --resource-group rg-ofppt-devtestlab --name ofppt-lab-formation --query "{Nom:name,Region:location,Statut:provisioningState}" -o table 2>&1

Write-Host ""
Write-Host "=== FORMULES ==="
& $az lab formula list --resource-group rg-ofppt-devtestlab --lab-name ofppt-lab-formation --query "[].{Formule:name,Taille:labVirtualMachineCreationParameter.size}" -o table 2>&1

Write-Host ""
Write-Host "=== POLITIQUES ACTIVES ==="
& $az lab policy list --resource-group rg-ofppt-devtestlab --lab-name ofppt-lab-formation --policy-set-name default --query "[?properties.status=='Enabled'].{Politique:name,Seuil:properties.threshold}" -o table 2>&1

Write-Host ""
Write-Host "=== URL PORTAIL STAGIAIRES ==="
Write-Host "https://labs.azure.com"
Write-Host ""
Write-Host "=== URL PORTAIL AZURE ==="
$sub = (& $az account show --query id -o tsv 2>&1) | Select-Object -Last 1
Write-Host "https://portal.azure.com/#resource/subscriptions/$sub/resourceGroups/rg-ofppt-devtestlab/providers/Microsoft.DevTestLab/labs/ofppt-lab-formation"
