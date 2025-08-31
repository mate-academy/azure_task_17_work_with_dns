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

Write-Host "Getting existing resource group ..."
$resourceGroup = Get-AzResourceGroup -Name $resourceGroupName -Location $location

if ($null -eq $resourceGroup)
{
    Write-Host "Resource group does not exist, creating ..."
    New-AzResourceGroup -Name $resourceGroupName -Location $location
}

Write-Host "Creating web network security group..."
$webNsg = Get-AzNetworkSecurityGroup -ResourceGroupName $resourceGroupName -Name $webSubnetName -ErrorAction SilentlyContinue
if ($null -eq $webNsg)
{
    $webHttpRule = New-AzNetworkSecurityRuleConfig -Name "web" -Description "Allow HTTP" `
       -Access Allow -Protocol Tcp -Direction Inbound -Priority 100 -SourceAddressPrefix `
       Internet -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 80,443
    $webNsg = New-AzNetworkSecurityGroup -ResourceGroupName $resourceGroupName -Location $location -Name `
       $webSubnetName -SecurityRules $webHttpRule
    Write-Host "Web network security group created."
}
else
{
    Write-Host "Web network security group already exists."
}

Write-Host "Creating mngSubnet network security group..."
$mngNsg = Get-AzNetworkSecurityGroup -ResourceGroupName $resourceGroupName -Name $mngSubnetName -ErrorAction SilentlyContinue
if ($null -eq $mngNsg)
{
    $mngSshRule = New-AzNetworkSecurityRuleConfig -Name "ssh" -Description "Allow SSH" `
       -Access Allow -Protocol Tcp -Direction Inbound -Priority 100 -SourceAddressPrefix `
       Internet -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 22
    $mngNsg = New-AzNetworkSecurityGroup -ResourceGroupName $resourceGroupName -Location $location -Name `
       $mngSubnetName -SecurityRules $mngSshRule
    Write-Host "Management network security group created."
}
else
{
    Write-Host "Management network security group already exists."
}

Write-Host "Creating a virtual network ..."
$virtualNetwork = Get-AzVirtualNetwork -Name $virtualNetworkName -ResourceGroupName $resourceGroupName -ErrorAction SilentlyContinue
if ($null -eq $virtualNetwork)
{
    $webSubnet = New-AzVirtualNetworkSubnetConfig -Name $webSubnetName -AddressPrefix $webSubnetIpRange -NetworkSecurityGroup $webNsg
    $mngSubnet = New-AzVirtualNetworkSubnetConfig -Name $mngSubnetName -AddressPrefix $mngSubnetIpRange -NetworkSecurityGroup $mngNsg
    $virtualNetwork = New-AzVirtualNetwork -Name $virtualNetworkName -ResourceGroupName $resourceGroupName -Location $location -AddressPrefix $vnetAddressPrefix -Subnet $webSubnet,$mngSubnet
    Write-Host "Virtual network created."
}
else
{
    Write-Host "Virtual network already exists."
}

Write-Host "Creating a SSH key resource ..."
$sshKey = Get-AzSshKey -Name $sshKeyName -ResourceGroupName $resourceGroupName -ErrorAction SilentlyContinue
if ($null -eq $sshKey)
{
    New-AzSshKey -Name $sshKeyName -ResourceGroupName $resourceGroupName -PublicKey $sshKeyPublicKey
    Write-Host "SSH key created."
}
else
{
    Write-Host "SSH key already exists."
}

Write-Host "Creating a web server VM ..."
$webVm = Get-AzVm -ResourceGroupName $resourceGroupName -Name $webVmName -ErrorAction SilentlyContinue
if ($null -eq $webVm)
{
    New-AzVm `
    -ResourceGroupName $resourceGroupName `
    -Name $webVmName `
    -Location $location `
    -image $vmImage `
    -size $vmSize `
    -SubnetName $webSubnetName `
    -VirtualNetworkName $virtualNetworkName `
    -SshKeyName $sshKeyName
    Write-Host "Web server VM created."
}
else
{
    Write-Host "Web server VM already exists."
}

$extension = Get-AzVMExtension -ResourceGroupName $resourceGroupName -VMName $webVmName -Name 'CustomScript' -ErrorAction SilentlyContinue
if ($null -eq $extension)
{
    $Params = @{
        ResourceGroupName = $resourceGroupName
        VMName = $webVmName
        Name = 'CustomScript'
        Publisher = 'Microsoft.Azure.Extensions'
        ExtensionType = 'CustomScript'
        TypeHandlerVersion = '2.1'
        Settings = @{ fileUris = @('https://raw.githubusercontent.com/mate-academy/azure_task_17_work_with_dns/main/install-app.sh'); commandToExecute = './install-app.sh' }
    }
    Set-AzVMExtension @Params
    Write-Host "Custom script extension added to web server VM."
}
else
{
    Write-Host "Custom script extension already exists on web server VM."
}

Write-Host "Creating a public IP ..."
$publicIP = Get-AzPublicIpAddress -Name $jumpboxVmName -ResourceGroupName $resourceGroupName -ErrorAction SilentlyContinue
if ($null -eq $publicIP)
{
    $publicIP = New-AzPublicIpAddress -Name $jumpboxVmName -ResourceGroupName $resourceGroupName -Location $location -Sku Standard -AllocationMethod Static -DomainNameLabel $dnsLabel
    Write-Host "Public IP created."
}
else
{
    Write-Host "Public IP already exists."
}

Write-Host "Creating a management VM ..."
$jumpboxVm = Get-AzVm -ResourceGroupName $resourceGroupName -Name $jumpboxVmName -ErrorAction SilentlyContinue
if ($null -eq $jumpboxVm)
{
    New-AzVm `
    -ResourceGroupName $resourceGroupName `
    -Name $jumpboxVmName `
    -Location $location `
    -image $vmImage `
    -size $vmSize `
    -SubnetName $mngSubnetName `
    -VirtualNetworkName $virtualNetworkName `
    -SshKeyName $sshKeyName `
    -PublicIpAddressName $jumpboxVmName
    Write-Host "Management VM created."
}
else
{
    Write-Host "Management VM already exists."
}

Write-Host "Creating private DNS zone ..."
$Zone = Get-AzPrivateDnsZone -Name $privateDnsZoneName -ResourceGroupName $resourceGroupName -ErrorAction SilentlyContinue
if ($null -eq $Zone)
{
    $Zone = New-AzPrivateDnsZone `
    -Name $privateDnsZoneName `
    -ResourceGroupName $resourceGroupName
    Write-Host "Private DNS zone created."
}
else
{
    Write-Host "Private DNS zone already exists."
}

Write-Host "Creating virtual network link ..."
$Link = Get-AzPrivateDnsVirtualNetworkLink -ZoneName $privateDnsZoneName -ResourceGroupName $resourceGroupName -Name "mylink" -ErrorAction SilentlyContinue
if ($null -eq $Link)
{
    $Link = New-AzPrivateDnsVirtualNetworkLink `
    -ZoneName $privateDnsZoneName `
    -ResourceGroupName $resourceGroupName `
    -Name "mylink" `
    -VirtualNetworkId $virtualNetwork.Id `
    -EnableRegistration
    Write-Host "Virtual network link created."
}
else
{
    Write-Host "Virtual network link already exists."
}

Write-Host "Waiting for web server A record to be auto-registered..."
$maxAttempts = 30
$attempt = 0
$webServerARecord = $null

do {
    $attempt++
    Write-Host "Checking for A record... Attempt $attempt of $maxAttempts"
    $webServerARecord = Get-AzPrivateDnsRecordSet -ZoneName $privateDnsZoneName -ResourceGroupName $resourceGroupName -Name $webVmName -RecordType A -ErrorAction SilentlyContinue
    if ($null -eq $webServerARecord) {
        Start-Sleep -Seconds 10
    }
} while ($null -eq $webServerARecord -and $attempt -lt $maxAttempts)

if ($null -eq $webServerARecord) {
    Write-Error "Web server A record was not auto-registered after waiting. Cannot create CNAME record."
    exit 1
}

Write-Host "Web server A record found. Creating CNAME record ..."
$RecordSet = Get-AzPrivateDnsRecordSet -ZoneName $privateDnsZoneName -ResourceGroupName $resourceGroupName -Name "todo" -RecordType CNAME -ErrorAction SilentlyContinue
if ($null -eq $RecordSet)
{
    $Records = @()
    $Records += New-AzPrivateDnsRecordConfig -Cname "$webVmName.$privateDnsZoneName"
    $RecordSet = New-AzPrivateDnsRecordSet `
    -Name "todo" `
    -RecordType CNAME `
    -ResourceGroupName $resourceGroupName `
    -TTL 3600 `
    -ZoneName $privateDnsZoneName `
    -PrivateDnsRecords $Records
    Write-Host "CNAME record created."
}
else
{
    Write-Host "CNAME record already exists."
}
