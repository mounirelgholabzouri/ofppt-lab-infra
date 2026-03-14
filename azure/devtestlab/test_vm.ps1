$az  = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd"
$RG  = "rg-ofppt-devtestlab"
$LAB = "ofppt-lab-formation"
$vmName = "test-vm-" + (Get-Date -Format "MMdd-HHmm")

Write-Host "=== Test creation VM DevTest Labs ===" -ForegroundColor Cyan
$sshKey = (Get-Content "C:\Users\Administrateur\.ssh\ofppt_azure.pub" -Raw).Trim()

Write-Host "Creation VM: $vmName (Ubuntu 22.04 / Standard_B2s)..." -ForegroundColor Green
$allOutput = & $az lab vm create `
    --lab-name $LAB `
    --resource-group $RG `
    --name $vmName `
    --image "Ubuntu Server 22.04 LTS" `
    --image-type gallery `
    --size Standard_B2s `
    --authentication-type ssh `
    --ssh-key $sshKey 2>&1

Write-Host "--- OUTPUT COMPLET ---" -ForegroundColor Yellow
$allOutput | ForEach-Object { Write-Host $_ }
Write-Host "--- FIN OUTPUT ---" -ForegroundColor Yellow

Write-Host "Exit code: $LASTEXITCODE" -ForegroundColor White
