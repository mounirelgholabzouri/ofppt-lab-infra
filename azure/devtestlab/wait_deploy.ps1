$az = 'C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd'
$status = 'Running'
$i = 0
while ($status -eq 'Running' -and $i -lt 20) {
    Start-Sleep -Seconds 30
    $i++
    $status = (& $az deployment group show --resource-group rg-ofppt-devtestlab --name ofppt-devtestlab-deploy --query 'properties.provisioningState' -o tsv 2>&1) | Select-Object -Last 1
    Write-Host "[$i] Statut : $status"
}
Write-Host "=== FINAL: $status ==="
if ($status -eq 'Succeeded') {
    Write-Host "DEPLOIEMENT_REUSSI"
    & $az lab show --resource-group rg-ofppt-devtestlab --name ofppt-lab-formation --query '{Lab:name, Region:location, Statut:provisioningState}' -o table 2>&1
} else {
    Write-Host "DEPLOIEMENT_ECHEC: $status"
    & $az deployment group operation list --resource-group rg-ofppt-devtestlab --name ofppt-devtestlab-deploy --query '[?properties.provisioningState==`Failed`].{Type:properties.targetResource.resourceType,Erreur:properties.statusMessage}' -o json 2>&1
}
