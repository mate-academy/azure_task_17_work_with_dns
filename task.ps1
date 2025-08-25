$location = "uksouth"
$resourceGroupName = "mate-azure-task-17"

$virtualNetworkName = "todoapp"
$vnetAddressPrefix = "10.20.30.0/24"
$webSubnetName = "webservers"
$webSubnetIpRange = "10.20.30.0/26"
$mngSubnetName = "management"
$mngSubnetIpRange = "10.20.30.128/26"

$sshKeyName = "linuxboxsshkey"

# --- SSH public key discovery (стійко) ---
$sshRsaPub = Join-Path $HOME ".ssh\id_rsa.pub"
$sshEdPub  = Join-Path $HOME ".ssh\id_ed25519.pub"
if (Test-Path $sshRsaPub) {
  $sshKeyPublicKey = Get-Content $sshRsaPub -Raw
} elseif (Test-Path $sshEdPub) {
  $sshKeyPublicKey = Get-Content $sshEdPub -Raw
} else {
  throw "SSH public key not found. Create one first: ssh-keygen -t rsa -b 4096 -f `"$HOME\.ssh\id_rsa`" -N `"`""
}

$vmImage = "Ubuntu2204"
$vmSize = "Standard_B1s"
$webVmName = "webserver"
$jumpboxVmName = "jumpbox"
$dnsLabel = "matetask" + (Get-Random -Count 1)

$privateDnsZoneName = "or.nottodo"

# --- Credentials для New-AzVm (логін через SSH-ключ; пароль тут технічний) ---
$adminUsername  = "azureuser"
$securePassword = ConvertTo-SecureString "P@ssw0rd1234!" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential ($adminUsername, $securePassword)

Write-Host "Creating a resource group $resourceGroupName ..."
New-AzResourceGroup -Name $resourceGroupName -Location $location

Write-Host "Creating web network security group..."
# ЄДИНЕ правило: дозволяємо 80/443/8080 з усього VNet (включно з management)
$webRule = New-AzNetworkSecurityRuleConfig -Name "web" -Description "Allow 80/443/8080 from VirtualNetwork" `
   -Access Allow -Protocol Tcp -Direction Inbound -Priority 100 `
   -SourceAddressPrefix VirtualNetwork -SourcePortRange * `
   -DestinationAddressPrefix * -DestinationPortRange 80,443,8080
$webNsg = New-AzNetworkSecurityGroup -ResourceGroupName $resourceGroupName -Location $location -Name `
   $webSubnetName -SecurityRules $webRule

Write-Host "Creating mngSubnet network security group..."
$mngSshRule = New-AzNetworkSecurityRuleConfig -Name "Allow-SSH" -Description "Allow SSH" `
   -Access Allow -Protocol Tcp -Direction Inbound -Priority 100 `
   -SourceAddressPrefix Internet -SourcePortRange * `
   -DestinationAddressPrefix * -DestinationPortRange 22
$mngNsg = New-AzNetworkSecurityGroup -ResourceGroupName $resourceGroupName -Location $location -Name `
   $mngSubnetName -SecurityRules $mngSshRule

Write-Host "Creating a virtual network ..."
$webSubnet = New-AzVirtualNetworkSubnetConfig -Name $webSubnetName -AddressPrefix $webSubnetIpRange -NetworkSecurityGroup $webNsg
$mngSubnet = New-AzVirtualNetworkSubnetConfig -Name $mngSubnetName -AddressPrefix $mngSubnetIpRange -NetworkSecurityGroup $mngNsg
$virtualNetwork = New-AzVirtualNetwork -Name $virtualNetworkName -ResourceGroupName $resourceGroupName -Location $location -AddressPrefix $vnetAddressPrefix -Subnet $webSubnet,$mngSubnet

Write-Host "Creating a SSH key resource ..."
Remove-AzSshKey -Name $sshKeyName -ResourceGroupName $resourceGroupName -ErrorAction SilentlyContinue
New-AzSshKey -Name $sshKeyName -ResourceGroupName $resourceGroupName -PublicKey $sshKeyPublicKey | Out-Null

Write-Host "Creating a web server VM ..."
New-AzVm `
  -ResourceGroupName $resourceGroupName `
  -Name $webVmName `
  -Location $location `
  -Image $vmImage `
  -Size $vmSize `
  -SubnetName $webSubnetName `
  -VirtualNetworkName $virtualNetworkName `
  -SshKeyName $sshKeyName `
  -Credential $cred

# Встановлюємо апку на webserver
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

Write-Host "Creating a public IP (Standard, Static) ..."
$publicIP = New-AzPublicIpAddress `
  -Name $jumpboxVmName `
  -ResourceGroupName $resourceGroupName `
  -Location $location `
  -Sku Standard `
  -AllocationMethod Static `
  -DomainNameLabel $dnsLabel

Write-Host "Creating a management VM (jumpbox) ..."
New-AzVm `
  -ResourceGroupName $resourceGroupName `
  -Name $jumpboxVmName `
  -Location $location `
  -Image $vmImage `
  -Size $vmSize `
  -SubnetName $mngSubnetName `
  -VirtualNetworkName $virtualNetworkName `
  -SshKeyName $sshKeyName `
  -PublicIpAddressName $jumpboxVmName `
  -Credential $cred

# ==============================
# Private DNS configuration
# ==============================
Write-Host "Creating Private DNS zone $privateDnsZoneName ..."
$dnsZone = New-AzPrivateDnsZone -Name $privateDnsZoneName -ResourceGroupName $resourceGroupName

Write-Host "Linking VNet '$virtualNetworkName' to DNS zone (auto-registration ON) ..."
$dnsVnetLinkName = "$($virtualNetworkName)-link"
New-AzPrivateDnsVirtualNetworkLink `
  -Name $dnsVnetLinkName `
  -ResourceGroupName $resourceGroupName `
  -ZoneName $privateDnsZoneName `
  -VirtualNetworkId $virtualNetwork.Id `
  -EnableRegistration | Out-Null

Write-Host "Creating CNAME record: todo.$privateDnsZoneName -> $webVmName.$privateDnsZoneName ..."
$records = @()
$records += New-AzPrivateDnsRecordConfig -Cname ("$($webVmName).$privateDnsZoneName")
New-AzPrivateDnsRecordSet `
  -Name "todo" `
  -RecordType CNAME `
  -ZoneName $privateDnsZoneName `
  -ResourceGroupName $resourceGroupName `
  -Ttl 300 `
  -PrivateDnsRecords $records | Out-Null

Write-Host "All resources deployed successfully."
