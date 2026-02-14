$location = "polandcentral"
$resourceGroupName = "mate-azure-task-17"

$virtualNetworkName = "todoapp"
$vnetAddressPrefix = "10.20.30.0/24"
$webSubnetName = "webservers"
$webSubnetIpRange = "10.20.30.0/26"
$mngSubnetName = "management"
$mngSubnetIpRange = "10.20.30.128/26"

$sshKeyName = "linuxboxsshkey"
$sshKeyPublicKey = Get-Content "C:\Users\Asus\.ssh\id_rsa_azure.pub"

$vmImage = "Ubuntu2404"
$vmSize = "Standard_B2ts_v2"
$webVmName = "webserver"
$jumpboxVmName = "jumpbox"
$dnsLabel = "matetask" + (Get-Random -Count 1)

$privateDnsZoneName = "or.nottodo"
$recordName = "todo"

Write-Host "Creating a resource group $resourceGroupName ..."
New-AzResourceGroup -Name $resourceGroupName -Location $location

Write-Host "Creating web network security group..."
$webHttpRule = New-AzNetworkSecurityRuleConfig -Name "web" `
   -Description "Allow HTTP" `
   -Access Allow `
   -Protocol Tcp `
   -Direction Inbound `
   -Priority 100 `
   -SourceAddressPrefix Internet `
   -SourcePortRange * `
   -DestinationAddressPrefix * `
   -DestinationPortRange 80, 443

$web8080Rule = New-AzNetworkSecurityRuleConfig `
   -Name "web-8080" `
   -Access Allow `
   -Protocol Tcp `
   -Direction Inbound `
   -Priority 110 `
   -SourceAddressPrefix VirtualNetwork `
   -SourcePortRange * `
   -DestinationAddressPrefix * `
   -DestinationPortRange 8080

$webNsg = New-AzNetworkSecurityGroup -ResourceGroupName $resourceGroupName `
   -Location $location `
   -Name $webSubnetName `
   -SecurityRules $webHttpRule, $web8080Rule

Write-Host "Creating mngSubnet network security group..."
$mngSshRule = New-AzNetworkSecurityRuleConfig -Name "ssh" `
   -Description "Allow SSH" `
   -Access Allow `
   -Protocol Tcp `
   -Direction Inbound `
   -Priority 100 `
   -SourceAddressPrefix Internet `
   -SourcePortRange * `
   -DestinationAddressPrefix * `
   -DestinationPortRange 22


$mngNsg = New-AzNetworkSecurityGroup -ResourceGroupName $resourceGroupName `
   -Location $location `
   -Name $mngSubnetName `
   -SecurityRules $mngSshRule

Write-Host "Creating a virtual network ..."
$webSubnet = New-AzVirtualNetworkSubnetConfig -Name $webSubnetName `
   -AddressPrefix $webSubnetIpRange `
   -NetworkSecurityGroup $webNsg

$mngSubnet = New-AzVirtualNetworkSubnetConfig -Name $mngSubnetName `
   -AddressPrefix $mngSubnetIpRange `
   -NetworkSecurityGroup $mngNsg

$virtualNetwork = New-AzVirtualNetwork -Name $virtualNetworkName `
   -ResourceGroupName $resourceGroupName `
   -Location $location `
   -AddressPrefix $vnetAddressPrefix `
   -Subnet $webSubnet, $mngSubnet

Write-Host "Creating a SSH key resource ..."
New-AzSshKey -Name $sshKeyName -ResourceGroupName $resourceGroupName -PublicKey $sshKeyPublicKey

Write-Host "Creating a web server VM ..."
New-AzVm `
   -ResourceGroupName $resourceGroupName `
   -Name $webVmName `
   -Location $location `
   -Image $vmImage `
   -Size $vmSize `
   -SubnetName $webSubnetName `
   -VirtualNetworkName $virtualNetworkName `
   -SshKeyName $sshKeyName

$Params = @{
   ResourceGroupName  = $resourceGroupName
   VMName             = $webVmName
   Name               = 'CustomScript'
   Publisher          = 'Microsoft.Azure.Extensions'
   ExtensionType      = 'CustomScript'
   TypeHandlerVersion = '2.1'
   Settings           = @{
      fileUris         = @('https://raw.githubusercontent.com/mate-academy/azure_task_17_work_with_dns/main/install-app.sh')
      commandToExecute = './install-app.sh'
   }
}
Set-AzVMExtension @Params

Write-Host "Creating a public IP ..."
$publicIP = New-AzPublicIpAddress -Name $jumpboxVmName `
   -ResourceGroupName $resourceGroupName `
   -Location $location `
   -Sku Standard `
   -AllocationMethod Static `
   -DomainNameLabel $dnsLabel

Write-Host "Creating a management VM ..."
New-AzVm `
   -ResourceGroupName $resourceGroupName `
   -Name $jumpboxVmName `
   -Location $location `
   -Image $vmImage `
   -Size $vmSize `
   -SubnetName $mngSubnetName `
   -VirtualNetworkName $virtualNetworkName `
   -SshKeyName $sshKeyName `
   -PublicIpAddressName $jumpboxVmName

Write-Host "Creating a private DNS zone ..."
New-AzPrivateDnsZone -Name $privateDnsZoneName -ResourceGroupName $resourceGroupName

Write-Host "Linking the virtual network to the private DNS zone ..."
New-AzPrivateDnsVirtualNetworkLink `
   -ResourceGroupName $resourceGroupName `
   -ZoneName $privateDnsZoneName `
   -Name "$virtualNetworkName-link" `
   -VirtualNetworkId $virtualNetwork.Id `
   -EnableRegistration


Write-Host "Creating a DNS record for the web server VM ..."
$rs = New-AzPrivateDnsRecordSet `
   -ResourceGroupName $resourceGroupName `
   -ZoneName $privateDnsZoneName `
   -Name $recordName `
   -RecordType CNAME `
   -Ttl 3600

$rs = Add-AzPrivateDnsRecordConfig `
   -RecordSet $rs `
   -Cname "$webVmName.$privateDnsZoneName"

Set-AzPrivateDnsRecordSet -RecordSet $rs
