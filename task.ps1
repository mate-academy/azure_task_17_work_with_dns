$location = "uksouth"
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

Write-Host "Creating private DNS zone $privateDnsZoneName ..."
$privateDnsZone = New-AzPrivateDnsZone `
    -ResourceGroupName $resourceGroupName `
    -Name $privateDnsZoneName

Write-Host "Linking DNS zone to virtual network with auto-registration..."
$link = New-AzPrivateDnsVirtualNetworkLink `
    -ResourceGroupName $resourceGroupName `
    -ZoneName $privateDnsZoneName `
    -Name "vnet-link" `
    -VirtualNetworkId $virtualNetwork.Id `
    -EnableRegistration

Write-Host "Creating a SSH key resource ..."
New-AzSshKey -Name $sshKeyName -ResourceGroupName $resourceGroupName -PublicKey $sshKeyPublicKey

Write-Host "Creating a web server VM ..."
$webVm = New-AzVm `
-ResourceGroupName $resourceGroupName `
-Name $webVmName `
-Location $location `
-Image $vmImage `
-Size $vmSize `
-SubnetName $webSubnetName `
-VirtualNetworkName $virtualNetworkName `
-SshKeyName $sshKeyName 

Write-Host "Installing web application..."
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

# Ключова зміна: використовуємо ім'я хоста замість IP-адреси
$targetFqdn = "$webVmName.$privateDnsZoneName"

Write-Host "Creating CNAME record for todo.or.nottodo pointing to $targetFqdn..."
$cnameRecord = New-AzPrivateDnsRecordConfig -Cname $targetFqdn
New-AzPrivateDnsRecordSet `
    -ResourceGroupName $resourceGroupName `
    -ZoneName $privateDnsZoneName `
    -Name "todo" `
    -RecordType CNAME `
    -Ttl 3600 `
    -PrivateDnsRecords $cnameRecord

Write-Host "Creating a public IP ..."
$publicIP = New-AzPublicIpAddress -Name $jumpboxVmName -ResourceGroupName $resourceGroupName -Location $location -Sku Basic -AllocationMethod Dynamic -DomainNameLabel $dnsLabel
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
