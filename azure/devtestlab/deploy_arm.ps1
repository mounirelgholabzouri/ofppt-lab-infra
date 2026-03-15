$sshKey = (Get-Content 'C:\Users\Administrateur\.ssh\ofppt_azure.pub' -Raw).Trim()
$az = 'C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd'

& $az deployment group create --resource-group rg-ofppt-devtestlab --template-file 'C:\Users\Administrateur\Desktop\ofppt-lab\azure\devtestlab\arm_lab_template.json' --parameters sshPublicKey="$sshKey" labName='ofppt-lab-formation' adminUsername='azureofppt' autoShutdownTime='2359' maxVmsPerUser=3 maxVmsPerLab=30 --name 'ofppt-devtestlab-deploy' 2>&1
