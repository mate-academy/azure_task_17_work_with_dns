$location =                             "uksouth"
$resourceGroupName =                    "mate-azure-task-17"

$virtualNetworkName =                   "todoapp"
$vnetAddressPrefix =                    "10.20.30.0/24"

$webSubnetName =                        "webservers"
$webSubnetIpRange =                     "10.20.30.0/26"

$mngSubnetName =                        "management"
$mngSubnetIpRange =                     "10.20.30.128/26"

$sshKeyName =                           "linuxboxsshkey"
$sshKeyPublicKey =                      Get-Content "~/.ssh/id_rsa.pub"

# Boot Diagnostic Storage Account settings
$bootStorageAccName =         "bootdiagnosstorageacc"
$bootStSkuName =              "Standard_LRS"
$bootStKind =                 "StorageV2"
$bootStAccessTier =           "Hot"
$bootStMinimumTlsVersion =    "TLS1_0"

# VM settings
$vmSize =                               "Standard_B1s"
$webVmName =                            "webserver"
$jumpboxVmName =                        "jumpbox"
$dnsLabel =                             "matetask" + (Get-Random -Count 1)
$privateDnsZoneName =                   "or.nottodo"

# OS settings:
$osUser =                               "yegor"
$osUserPassword =                       "P@ssw0rd1234"
  $SecuredPassword = ConvertTo-SecureString `
    $osUserPassword -AsPlainText -Force
  $cred = New-Object System.Management.Automation.PSCredential `
    ($osUser, $SecuredPassword)
$osPublisherName =                      "Canonical"
$osOffer =                              "0001-com-ubuntu-server-jammy"
$osSku =                                "22_04-lts-gen2"
$osVersion =                            "latest"
$osDiskSizeGB =                         64
$osDiskType =                           "Premium_LRS"


Write-Host "Creating a resource group $resourceGroupName ..."
New-AzResourceGroup `
  -Name                                 $resourceGroupName `
  -Location                             $location

Write-Host "Creating web network security group..."
$webHttpRule = New-AzNetworkSecurityRuleConfig `
  -Name                                 "web" `
  -Description                          "Allow HTTP" `
  -Access                               "Allow" `
  -Protocol                             "Tcp" `
  -Direction                            "Inbound" `
  -Priority                             100 `
  -SourceAddressPrefix                  "Internet" `
  -SourcePortRange                      * `
  -DestinationAddressPrefix             * `
  -DestinationPortRange                 80,443
$webNsg = New-AzNetworkSecurityGroup `
  -ResourceGroupName                    $resourceGroupName `
  -Location                             $location `
  -Name                                 $webSubnetName `
  -SecurityRules                        $webHttpRule

Write-Host "Creating mngSubnet network security group..."
$mngSshRule = New-AzNetworkSecurityRuleConfig `
  -Name                                 "ssh" `
  -Description                          "Allow SSH" `
  -Access                               "Allow" `
  -Protocol                             "Tcp" `
  -Direction                            "Inbound" `
  -Priority                             100 `
  -SourceAddressPrefix                  "Internet" `
  -SourcePortRange                      * `
  -DestinationAddressPrefix             * `
  -DestinationPortRange                 22
$mngNsg = New-AzNetworkSecurityGroup `
  -ResourceGroupName                    $resourceGroupName `
  -Location                             $location `
  -Name                                 $mngSubnetName `
  -SecurityRules                        $mngSshRule

Write-Host "Creating a virtual network ..."
$webSubnet = New-AzVirtualNetworkSubnetConfig `
  -Name                                 $webSubnetName `
  -AddressPrefix                        $webSubnetIpRange `
  -NetworkSecurityGroup                 $webNsg
$mngSubnet = New-AzVirtualNetworkSubnetConfig `
  -Name                                 $mngSubnetName `
  -AddressPrefix                        $mngSubnetIpRange `
  -NetworkSecurityGroup                 $mngNsg
New-AzVirtualNetwork `
  -Name                                 $virtualNetworkName `
  -ResourceGroupName                    $resourceGroupName `
  -Location                             $location `
  -AddressPrefix                        $vnetAddressPrefix `
  -Subnet                               $webSubnet,`
                                        $mngSubnet
  $vnetObj = Get-AzVirtualNetwork `
    -Name                               $virtualNetworkName `
    -ResourceGroupName                  $resourceGroupName
  $webSubnetId = (
    $vnetObj.Subnets |
    Where-Object { $_.Name -eq $webSubnetName }
    ).Id
  $mngSubnetId = (
    $vnetObj.Subnets |
    Where-Object { $_.Name -eq $mngSubnetName }
    ).Id

Write-Host "Creating Storage Account for boot diagnostic ..."
New-AzStorageAccount `
  -ResourceGroupName                    $resourceGroupName `
  -Name                                 $bootStorageAccName `
  -Location                             $location `
  -SkuName                              $bootStSkuName `
  -Kind                                 $bootStKind `
  -AccessTier                           $bootStAccessTier `
  -MinimumTlsVersion                    $bootStMinimumTlsVersion

Write-Host "Creating a NIC for web server VM ..."
$ipConfig = New-AzNetworkInterfaceIpConfig `
  -Name                                 "${webVmName}-ipconfig" `
  -SubnetId                             $webSubnetId
New-AzNetworkInterface -Force `
  -Name                                 "${webVmName}-NIC" `
  -ResourceGroupName                    $resourceGroupName `
  -Location                             $location `
  -IpConfiguration                      $ipConfig
  $nicObj = Get-AzNetworkInterface `
    -Name                               "${webVmName}-NIC" `
    -ResourceGroupName                  $resourceGroupName
Write-Host "Creating a web server VM ..."
$vmconfig = New-AzVMConfig `
  -VMName                               $webVmName `
  -VMSize                               $vmSize
$vmconfig = Set-AzVMSourceImage `
  -VM                                   $vmconfig `
  -PublisherName                        $osPublisherName `
  -Offer                                $osOffer `
  -Skus                                 $osSku `
  -Version                              $osVersion
$vmconfig = Set-AzVMOSDisk `
  -VM                                   $vmconfig `
  -Name                                 "${webVmName}-OSDisk" `
  -CreateOption                         "FromImage" `
  -DeleteOption                         "Delete" `
  -DiskSizeInGB                         $osDiskSizeGB `
  -Caching                              "ReadWrite" `
  -StorageAccountType                   $osDiskType
$vmconfig = Set-AzVMOperatingSystem `
  -VM                                   $vmconfig `
  -ComputerName                         $webVmName `
  -Linux                                `
  -Credential                           $cred
$vmconfig = Add-AzVMNetworkInterface `
  -VM                                   $vmconfig `
  -Id                                   $nicObj.Id
$vmconfig = Set-AzVMBootDiagnostic `
  -VM                                   $vmconfig `
  -Enable                               `
  -ResourceGroupName                    $resourceGroupName `
  -StorageAccountName                   $bootStorageAccName
New-AzVM `
  -ResourceGroupName                    $resourceGroupName `
  -Location                             $location `
  -VM                                   $vmconfig
$scriptUrl = "https://github.com/YegorVolkov/azure_task_17_work_with_dns/blob/dev/install-app.sh"
Set-AzVMExtension `
  -ResourceGroupName                    $resourceGroupName `
  -VMName                               $webVmName `
  -Name                                 'CustomScript' `
  -Publisher                            'Microsoft.Azure.Extensions' `
  -ExtensionType                        'CustomScript' `
  -TypeHandlerVersion                   '2.1' `
  -Settings @{
      "fileUris" =                      @($scriptUrl)
      "commandToExecute" =              './install-app.sh'
  }


Write-Host "Creating an SSH key resource ..."
New-AzSshKey `
  -Name                                 $sshKeyName `
  -ResourceGroupName                    $resourceGroupName `
  -PublicKey                            $sshKeyPublicKey
Write-Host "Creating a public IP ..."
New-AzPublicIpAddress `
  -Name                                 "${jumpboxVmName}-pubip" `
  -ResourceGroupName                    $resourceGroupName `
  -Location                             $location `
  -Sku                                  "Basic" `
  -AllocationMethod                     "Dynamic" `
  -DomainNameLabel                      $dnsLabel
  $jumpboxVmPubipObj = Get-AzPublicIpAddress `
    -Name                               "${jumpboxVmName}-pubip" `
    -ResourceGroupName                  $resourceGroupName
Write-Host "Creating a NIC for management VM ..."
$ipConfig = New-AzNetworkInterfaceIpConfig `
  -Name                                 "${jumpboxVmName}-ipconfig" `
  -SubnetId                             $mngSubnetId `
  -PublicIpAddressId                    $jumpboxVmPubipObj.Id
New-AzNetworkInterface -Force `
  -Name                                 "${jumpboxVmName}-NIC" `
  -ResourceGroupName                    $resourceGroupName `
  -Location                             $location `
  -IpConfiguration                      $ipConfig
  $nicObj = Get-AzNetworkInterface `
    -Name                               "${jumpboxVmName}-NIC" `
    -ResourceGroupName                  $resourceGroupName
Write-Host "Creating a management VM ..."
$vmconfig = New-AzVMConfig `
  -VMName                               $jumpboxVmName `
  -VMSize                               $vmSize `
$vmconfig = Set-AzVMSourceImage `
  -VM                                   $vmconfig `
  -PublisherName                        $osPublisherName `
  -Offer                                $osOffer `
  -Skus                                 $osSku `
  -Version                              $osVersion
$vmconfig = Set-AzVMOSDisk `
  -VM                                   $vmconfig `
  -Name                                 "${jumpboxVmName}-OSDisk" `
  -CreateOption                         FromImage `
  -DeleteOption                         Delete `
  -DiskSizeInGB                         $osDiskSizeGB `
  -Caching                              ReadWrite `
  -StorageAccountType                   $osDiskType
$vmconfig = Set-AzVMOperatingSystem `
  -VM                                   $vmconfig `
  -ComputerName                         $jumpboxVmName `
  -Linux                                `
  -Credential                           $cred `
  -DisablePasswordAuthentication
$vmconfig = Add-AzVMNetworkInterface `
  -VM                                   $vmconfig `
  -Id                                   $nicObj.Id
$vmconfig = Set-AzVMBootDiagnostic `
  -VM                                   $vmconfig `
  -Enable                               `
  -ResourceGroupName                    $resourceGroupName `
  -StorageAccountName                   $bootStorageAccName
New-AzVM `
  -ResourceGroupName                    $resourceGroupName `
  -Location                             $location `
  -VM                                   $vmconfig `
  -SshKeyName                           $sshKeyName

New-AzPrivateDnsZone `
  -Name                                 $privateDnsZoneName `
  -ResourceGroupName                    $resourceGroupName

New-AzPrivateDnsVirtualNetworkLink `
  -Name                                 "${$privateDnsZoneName}-Link" `
  -ResourceGroupName                    $resourceGroupName `
  -ZoneName                             $privateDnsZoneName `
  -VirtualNetwork                       $vnetObj.Id `
  -EnableRegistration

New-AzPrivateDnsRecordSet `
  -Name                                 "${webVmName}.${privateDnsZoneName}" `
  -RecordType                           CNAME `
  -ResourceGroupName                    $resourceGroupName `
  -TTL                                  3600 `
  -ZoneName                             $privateDnsZoneName `
  -PrivateDnsRecords                    @(
    New-AzPrivateDnsRecordConfig `
      -Cname                            "todo.${privateDnsZoneName}"
    )
