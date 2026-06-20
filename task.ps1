$location = "denmarkeast"
$resourceGroupName = "mate-azure-task-17"

$virtualNetworkName = "todoapp"
$vnetAddressPrefix = "10.20.30.0/24"
$webSubnetName = "webservers"
$webSubnetIpRange = "10.20.30.0/26"
$mngSubnetName = "management"
$mngSubnetIpRange = "10.20.30.128/26"

$sshKeyName = "linuxboxsshkey"
$sshKeyPublicKey = Get-Content "~/.ssh/id_rsa.pub"

$vmImage = "Ubuntu2204"
$vmSize = "Standard_B1s"
$webVmName = "webserver"
$jumpboxVmName = "jumpbox"
$dnsLabel = "matetask" + (Get-Random -Count 1)

$privateDnsZoneName = "or.nottodo"


Write-Host "Creating a resource group $resourceGroupName ..."
New-AzResourceGroup -Name $resourceGroupName -Location $location

Write-Host "Creating web network security group..."
$webHttpRule = New-AzNetworkSecurityRuleConfig -Name "web" -Description "Allow HTTP" `
   -Access Allow -Protocol Tcp -Direction Inbound -Priority 100 -SourceAddressPrefix `
   Internet -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 80,443
$webNsg = New-AzNetworkSecurityGroup -ResourceGroupName $resourceGroupName -Location $location -Name `
   $webSubnetName -SecurityRules $webHttpRule

Write-Host "Creating mngSubnet network security group..."
$mngSshRule = New-AzNetworkSecurityRuleConfig -Name "ssh" -Description "Allow SSH" `
   -Access Allow -Protocol Tcp -Direction Inbound -Priority 100 -SourceAddressPrefix `
   Internet -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 22
$mngNsg = New-AzNetworkSecurityGroup -ResourceGroupName $resourceGroupName -Location $location -Name `
   $mngSubnetName -SecurityRules $mngSshRule

Write-Host "Creating a virtual network ..."
$webSubnet = New-AzVirtualNetworkSubnetConfig -Name $webSubnetName -AddressPrefix $webSubnetIpRange -NetworkSecurityGroup $webNsg
$mngSubnet = New-AzVirtualNetworkSubnetConfig -Name $mngSubnetName -AddressPrefix $mngSubnetIpRange -NetworkSecurityGroup $mngNsg
$virtualNetwork = New-AzVirtualNetwork -Name $virtualNetworkName -ResourceGroupName $resourceGroupName -Location $location -AddressPrefix $vnetAddressPrefix -Subnet $webSubnet,$mngSubnet

Write-Host "Creating a SSH key resource ..."
New-AzSshKey -Name $sshKeyName -ResourceGroupName $resourceGroupName -PublicKey $sshKeyPublicKey
do { Start-Sleep -Seconds 10 } until (Get-AzSshKey -Name $sshKeyName -ResourceGroupName $resourceGroupName -ErrorAction SilentlyContinue)

$adminCredential = New-Object System.Management.Automation.PSCredential ("azureuser", (ConvertTo-SecureString "Mate2026!Secure" -AsPlainText -Force))

Write-Host "Creating a web server VM ..."
$webNic = New-AzNetworkInterface -Name "$webVmName-nic" -ResourceGroupName $resourceGroupName -Location $location -SubnetId ($virtualNetwork.Subnets | Where-Object { $_.Name -eq $webSubnetName }).Id
$webVmConfig = New-AzVMConfig -VMName $webVmName -VMSize $vmSize
$webVmConfig = Set-AzVMOperatingSystem -VM $webVmConfig -Linux -ComputerName $webVmName -Credential $adminCredential -DisablePasswordAuthentication
$webVmConfig = Set-AzVMSourceImage -VM $webVmConfig -PublisherName "Canonical" -Offer "0001-com-ubuntu-server-jammy" -Skus "22_04-lts-gen2" -Version "latest"
$webVmConfig = Add-AzVMNetworkInterface -VM $webVmConfig -Id $webNic.Id
$webVmConfig = Add-AzVMSshPublicKey -VM $webVmConfig -KeyData $sshKeyPublicKey -Path "/home/azureuser/.ssh/authorized_keys"
New-AzVM -ResourceGroupName $resourceGroupName -Location $location -VM $webVmConfig
$Params = @{
    ResourceGroupName  = $resourceGroupName
    VMName             = $webVmName
    Name               = 'CustomScript'
    Publisher          = 'Microsoft.Azure.Extensions'
    ExtensionType      = 'CustomScript'
    TypeHandlerVersion = '2.1'
    Settings          = @{fileUris = @('https://raw.githubusercontent.com/mate-academy/azure_task_17_work_with_dns/main/install-app.sh'); commandToExecute = './install-app.sh'}
 }
Set-AzVMExtension @Params

Write-Host "Creating a public IP ..."
$publicIP = New-AzPublicIpAddress -Name $jumpboxVmName -ResourceGroupName $resourceGroupName -Location $location -Sku Standard -AllocationMethod Static -DomainNameLabel $dnsLabel
Write-Host "Creating a management VM ..."
$jumpboxNic = New-AzNetworkInterface -Name "$jumpboxVmName-nic" -ResourceGroupName $resourceGroupName -Location $location -SubnetId ($virtualNetwork.Subnets | Where-Object { $_.Name -eq $mngSubnetName }).Id -PublicIpAddressId $publicIP.Id
$jumpboxVmConfig = New-AzVMConfig -VMName $jumpboxVmName -VMSize $vmSize
$jumpboxVmConfig = Set-AzVMOperatingSystem -VM $jumpboxVmConfig -Linux -ComputerName $jumpboxVmName -Credential $adminCredential -DisablePasswordAuthentication
$jumpboxVmConfig = Set-AzVMSourceImage -VM $jumpboxVmConfig -PublisherName "Canonical" -Offer "0001-com-ubuntu-server-jammy" -Skus "22_04-lts-gen2" -Version "latest"
$jumpboxVmConfig = Add-AzVMNetworkInterface -VM $jumpboxVmConfig -Id $jumpboxNic.Id
$jumpboxVmConfig = Add-AzVMSshPublicKey -VM $jumpboxVmConfig -KeyData $sshKeyPublicKey -Path "/home/azureuser/.ssh/authorized_keys"
New-AzVM -ResourceGroupName $resourceGroupName -Location $location -VM $jumpboxVmConfig


# Write your code here  ->

Write-Host "Creating a private DNS zone $privateDnsZoneName ..."
$privateDnsZone = New-AzPrivateDnsZone -ResourceGroupName $resourceGroupName -Name $privateDnsZoneName

Write-Host "Linking the private DNS zone to the virtual network ..."
New-AzPrivateDnsVirtualNetworkLink -ResourceGroupName $resourceGroupName -ZoneName $privateDnsZoneName -Name "$virtualNetworkName-link" -VirtualNetworkId $virtualNetwork.Id -EnableRegistration

Write-Host "Creating a CNAME record todo.$privateDnsZoneName ..."
$cnameRecord = New-AzPrivateDnsRecordConfig -Cname "$webVmName.$privateDnsZoneName"
New-AzPrivateDnsRecordSet -ResourceGroupName $resourceGroupName -ZoneName $privateDnsZoneName -Name "todo" -RecordType CNAME -Ttl 3600 -PrivateDnsRecords $cnameRecord
