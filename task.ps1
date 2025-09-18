$location = "uksouth"
$resourceGroupName = "mate-resources"

$virtualNetworkName = "todoapp"
$vnetAddressPrefix = "10.20.30.0/24"
$webSubnetName = "web"
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


# -------------------------------
# Resource Group (idempotent)
# -------------------------------
$rg = Get-AzResourceGroup -Name $resourceGroupName -ErrorAction SilentlyContinue
if (-not $rg) {
    Write-Host "Creating resource group $resourceGroupName ..."
    New-AzResourceGroup -Name $resourceGroupName -Location $location | Out-Null
} else {
    Write-Host "Resource group $resourceGroupName already exists, skipping."
}

# -------------------------------
# Web NSG (idempotent)
# -------------------------------
Write-Host "Ensuring web NSG exists with correct rules ..."
$webNsg = Get-AzNetworkSecurityGroup -Name $webSubnetName -ResourceGroupName $resourceGroupName -ErrorAction SilentlyContinue
if (-not $webNsg) {
    # Allow 80/443 from Internet
    $webHttpRule = New-AzNetworkSecurityRuleConfig -Name "web" -Description "Allow HTTP/HTTPS from Internet" `
       -Access Allow -Protocol Tcp -Direction Inbound -Priority 100 -SourceAddressPrefix Internet `
       -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRanges @('80','443')
    # Allow 8080 from inside VNet
    $web8080Rule = New-AzNetworkSecurityRuleConfig -Name "app-8080" -Description "Allow app port from VNet" `
       -Access Allow -Protocol Tcp -Direction Inbound -Priority 110 -SourceAddressPrefix VirtualNetwork `
       -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 8080
    $webNsg = New-AzNetworkSecurityGroup -ResourceGroupName $resourceGroupName -Location $location -Name $webSubnetName -SecurityRules $webHttpRule,$web8080Rule
} else {
    Write-Host "Web NSG $webSubnetName exists, skipping creation."
}

# -------------------------------
# Management NSG (idempotent)
# -------------------------------
Write-Host "Ensuring management NSG exists ..."
$mngNsg = Get-AzNetworkSecurityGroup -Name $mngSubnetName -ResourceGroupName $resourceGroupName -ErrorAction SilentlyContinue
if (-not $mngNsg) {
    $mngSshRule = New-AzNetworkSecurityRuleConfig -Name "ssh" -Description "Allow SSH" `
       -Access Allow -Protocol Tcp -Direction Inbound -Priority 100 -SourceAddressPrefix Internet `
       -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 22
    $mngNsg = New-AzNetworkSecurityGroup -ResourceGroupName $resourceGroupName -Location $location -Name $mngSubnetName -SecurityRules $mngSshRule
} else {
    Write-Host "Management NSG $mngSubnetName exists, skipping creation."
}

# -------------------------------
# Virtual Network (idempotent)
# -------------------------------
Write-Host "Ensuring virtual network exists ..."
$virtualNetwork = Get-AzVirtualNetwork -Name $virtualNetworkName -ResourceGroupName $resourceGroupName -ErrorAction SilentlyContinue
if (-not $virtualNetwork) {
    $webSubnet = New-AzVirtualNetworkSubnetConfig -Name $webSubnetName -AddressPrefix $webSubnetIpRange -NetworkSecurityGroup $webNsg
    $mngSubnet = New-AzVirtualNetworkSubnetConfig -Name $mngSubnetName -AddressPrefix $mngSubnetIpRange -NetworkSecurityGroup $mngNsg
    $virtualNetwork = New-AzVirtualNetwork -Name $virtualNetworkName -ResourceGroupName $resourceGroupName -Location $location -AddressPrefix $vnetAddressPrefix -Subnet $webSubnet,$mngSubnet
} else {
    Write-Host "Virtual network $virtualNetworkName exists, skipping creation."
}

# -------------------------------
# SSH Key (idempotent)
# -------------------------------
Write-Host "Ensuring SSH key resource exists ..."
$sshKey = Get-AzSshKey -Name $sshKeyName -ResourceGroupName $resourceGroupName -ErrorAction SilentlyContinue
if (-not $sshKey) {
    New-AzSshKey -Name $sshKeyName -ResourceGroupName $resourceGroupName -PublicKey $sshKeyPublicKey | Out-Null
} else {
    Write-Host "SSH key $sshKeyName exists, skipping."
}

# -------------------------------
# Web Server VM (idempotent)
# -------------------------------
Write-Host "Ensuring web server VM exists ..."
$webVm = Get-AzVm -Name $webVmName -ResourceGroupName $resourceGroupName -ErrorAction SilentlyContinue
if (-not $webVm) {
    New-AzVm `
    -ResourceGroupName $resourceGroupName `
    -Name $webVmName `
    -Location $location `
    -Image $vmImage `
    -Size $vmSize `
    -SubnetName $webSubnetName `
    -VirtualNetworkName $virtualNetworkName `
    -SshKeyName $sshKeyName | Out-Null

    $Params = @{
        ResourceGroupName  = $resourceGroupName
        VMName             = $webVmName
        Name               = 'CustomScript'
        Publisher          = 'Microsoft.Azure.Extensions'
        ExtensionType      = 'CustomScript'
        TypeHandlerVersion = '2.1'
        Settings           = @{fileUris = @('https://raw.githubusercontent.com/mate-academy/azure_task_17_work_with_dns/main/install-app.sh'); commandToExecute = './install-app.sh'}
    }
    Set-AzVMExtension @Params | Out-Null
} else {
    Write-Host "Web server VM $webVmName exists, skipping creation."
}

# -------------------------------
# Public IP (idempotent)
# -------------------------------
Write-Host "Ensuring public IP exists ..."
$publicIP = Get-AzPublicIpAddress -Name $jumpboxVmName -ResourceGroupName $resourceGroupName -ErrorAction SilentlyContinue
if (-not $publicIP) {
    $publicIP = New-AzPublicIpAddress -Name $jumpboxVmName -ResourceGroupName $resourceGroupName -Location $location -Sku Basic -AllocationMethod Dynamic -DomainNameLabel $dnsLabel
} else {
    Write-Host "Public IP $jumpboxVmName exists, skipping creation."
}

# -------------------------------
# Management VM (idempotent)
# -------------------------------
Write-Host "Ensuring management VM exists ..."
$jumpVm = Get-AzVm -Name $jumpboxVmName -ResourceGroupName $resourceGroupName -ErrorAction SilentlyContinue
if (-not $jumpVm) {
    New-AzVm `
    -ResourceGroupName $resourceGroupName `
    -Name $jumpboxVmName `
    -Location $location `
    -Image $vmImage `
    -Size $vmSize `
    -SubnetName $mngSubnetName `
    -VirtualNetworkName $virtualNetworkName `
    -SshKeyName $sshKeyName `
    -PublicIpAddressName $jumpboxVmName | Out-Null
} else {
    Write-Host "Management VM $jumpboxVmName exists, skipping creation."
}

# -------------------------------
# Private DNS Zone
# -------------------------------
$dnsZone = Get-AzPrivateDnsZone -Name $privateDnsZoneName -ResourceGroupName $resourceGroupName -ErrorAction SilentlyContinue
if (-not $dnsZone) {
    Write-Host "Creating private DNS zone $privateDnsZoneName ..."
    $dnsZone = New-AzPrivateDnsZone -Name $privateDnsZoneName -ResourceGroupName $resourceGroupName
} else {
    Write-Host "Private DNS zone $privateDnsZoneName exists, skipping."
}

# Link the zone to the VNet with auto-registration
$dnsLinkName = "$($virtualNetworkName)-link"
$existingLinks = Get-AzPrivateDnsVirtualNetworkLink -ZoneName $privateDnsZoneName -ResourceGroupName $resourceGroupName -ErrorAction SilentlyContinue
$dnsLink = $existingLinks | Where-Object { $_.Name -eq $dnsLinkName }
if (-not $dnsLink) {
    Write-Host "Creating VNet link $dnsLinkName with auto-registration ..."
    New-AzPrivateDnsVirtualNetworkLink `
        -ZoneName $privateDnsZoneName `
        -ResourceGroupName $resourceGroupName `
        -Name $dnsLinkName `
        -VirtualNetworkId $virtualNetwork.Id `
        -EnableRegistration | Out-Null
} else {
    Write-Host "VNet link '$dnsLinkName' exists, skipping."
}

# Poll for A-record auto-registration to avoid race condition
Write-Host "Waiting for A record '$webVmName.$privateDnsZoneName' auto-registration ..."
$maxAttempts = 30
$attempt = 0
$webARecord = $null
do {
    $webARecord = Get-AzPrivateDnsRecordSet -ZoneName $privateDnsZoneName -ResourceGroupName $resourceGroupName -Name $webVmName -RecordType A -ErrorAction SilentlyContinue
    if ($webARecord) { break }
    Start-Sleep -Seconds 10
    $attempt++
} while ($attempt -lt $maxAttempts)
if (-not $webARecord) {
    Write-Host "Timed out waiting for A record for $webVmName. Proceeding to create CNAME anyway."
}

# CNAME: todo -> webserver.or.nottodo
$recordName = "todo"
$dnsRecord = Get-AzPrivateDnsRecordSet -ZoneName $privateDnsZoneName -ResourceGroupName $resourceGroupName -Name $recordName -RecordType CNAME -ErrorAction SilentlyContinue
if (-not $dnsRecord) {
    Write-Host "Creating CNAME record $recordName.$privateDnsZoneName -> webserver.$privateDnsZoneName ..."
    New-AzPrivateDnsRecordSet `
        -ZoneName $privateDnsZoneName `
        -ResourceGroupName $resourceGroupName `
        -Name $recordName `
        -RecordType "CNAME" `
        -Ttl 300 `
        -PrivateDnsRecords (New-AzPrivateDnsRecordConfig -Cname "webserver.$privateDnsZoneName")
} else {
    Write-Host "CNAME record $recordName.$privateDnsZoneName exists, skipping."
}
