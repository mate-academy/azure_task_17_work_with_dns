$location = "uksouth"
$resourceGroupName = "mate-resources"

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

try {
    Write-Host "=== Azure DNS Zone Deployment ==="

    Write-Host "Creating a resource group $resourceGroupName ..."
    $resourceGroup = Get-AzResourceGroup -Name $resourceGroupName -ErrorAction SilentlyContinue
    if (-not $resourceGroup) {
        $resourceGroup = New-AzResourceGroup -Name $resourceGroupName -Location $location
        Write-Host "✅ Resource group created"
    } else {
        Write-Host "ℹ️ Resource group already exists"
    }

    Write-Host "Creating web network security group..."
    $webNsg = Get-AzNetworkSecurityGroup -ResourceGroupName $resourceGroupName -Name $webSubnetName -ErrorAction SilentlyContinue
    if (-not $webNsg) {
        $webHttpRule = New-AzNetworkSecurityRuleConfig -Name "web" -Description "Allow HTTP" `
           -Access Allow -Protocol Tcp -Direction Inbound -Priority 100 -SourceAddressPrefix `
           Internet -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 80,443
        $webNsg = New-AzNetworkSecurityGroup -ResourceGroupName $resourceGroupName -Location $location -Name `
           $webSubnetName -SecurityRules $webHttpRule
        Write-Host "✅ Web NSG created"
    } else {
        Write-Host "ℹ️ Web NSG already exists"
    }

    Write-Host "Creating management network security group..."
    $mngNsg = Get-AzNetworkSecurityGroup -ResourceGroupName $resourceGroupName -Name $mngSubnetName -ErrorAction SilentlyContinue
    if (-not $mngNsg) {
        $mngSshRule = New-AzNetworkSecurityRuleConfig -Name "ssh" -Description "Allow SSH" `
           -Access Allow -Protocol Tcp -Direction Inbound -Priority 100 -SourceAddressPrefix `
           Internet -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 22
        $mngNsg = New-AzNetworkSecurityGroup -ResourceGroupName $resourceGroupName -Location $location -Name `
           $mngSubnetName -SecurityRules $mngSshRule
        Write-Host "✅ Management NSG created"
    } else {
        Write-Host "ℹ️ Management NSG already exists"
    }

    Write-Host "Creating a virtual network ..."
    $virtualNetwork = Get-AzVirtualNetwork -Name $virtualNetworkName -ResourceGroupName $resourceGroupName -ErrorAction SilentlyContinue
    if (-not $virtualNetwork) {
        $webSubnet = New-AzVirtualNetworkSubnetConfig -Name $webSubnetName -AddressPrefix $webSubnetIpRange -NetworkSecurityGroup $webNsg
        $mngSubnet = New-AzVirtualNetworkSubnetConfig -Name $mngSubnetName -AddressPrefix $mngSubnetIpRange -NetworkSecurityGroup $mngNsg
        $virtualNetwork = New-AzVirtualNetwork -Name $virtualNetworkName -ResourceGroupName $resourceGroupName -Location $location -AddressPrefix $vnetAddressPrefix -Subnet $webSubnet,$mngSubnet
        Write-Host "✅ Virtual network created"
    } else {
        Write-Host "ℹ️ Virtual network already exists"
    }

    # Create Private DNS Zone with idempotency
    Write-Host "Creating Private DNS Zone: $privateDnsZoneName ..."
    $privateDnsZone = Get-AzPrivateDnsZone -ResourceGroupName $resourceGroupName -Name $privateDnsZoneName -ErrorAction SilentlyContinue
    if (-not $privateDnsZone) {
        $privateDnsZone = New-AzPrivateDnsZone `
            -ResourceGroupName $resourceGroupName `
            -Name $privateDnsZoneName
        Write-Host "✅ Private DNS Zone created"
    } else {
        Write-Host "ℹ️ Private DNS Zone already exists"
    }

    # Link Private DNS Zone with Virtual Network with auto-registration and idempotency
    Write-Host "Linking Private DNS Zone with Virtual Network..."
    $vnetLinkName = "${virtualNetworkName}-link"
    $vnetLink = Get-AzPrivateDnsVirtualNetworkLink -ResourceGroupName $resourceGroupName -ZoneName $privateDnsZoneName -Name $vnetLinkName -ErrorAction SilentlyContinue
    if (-not $vnetLink) {
        $vnetLink = New-AzPrivateDnsVirtualNetworkLink `
            -ResourceGroupName $resourceGroupName `
            -ZoneName $privateDnsZoneName `
            -Name $vnetLinkName `
            -VirtualNetworkId $virtualNetwork.Id `
            -EnableRegistration:$true
        Write-Host "✅ VNet link created with auto-registration"
    } else {
        Write-Host "ℹ️ VNet link already exists"
    }

    Write-Host "Creating a SSH key resource ..."
    $sshKey = Get-AzSshKey -Name $sshKeyName -ResourceGroupName $resourceGroupName -ErrorAction SilentlyContinue
    if (-not $sshKey) {
        New-AzSshKey -Name $sshKeyName -ResourceGroupName $resourceGroupName -PublicKey $sshKeyPublicKey
        Write-Host "✅ SSH key created"
    } else {
        Write-Host "ℹ️ SSH key already exists"
    }

    # Create Network Interfaces first
    Write-Host "Creating network interfaces..."
    
    # Web server NIC
    $webNicName = "${webVmName}-nic"
    $webNic = Get-AzNetworkInterface -Name $webNicName -ResourceGroupName $resourceGroupName -ErrorAction SilentlyContinue
    if (-not $webNic) {
        $webSubnetObj = Get-AzVirtualNetworkSubnetConfig -Name $webSubnetName -VirtualNetwork $virtualNetwork
        $webNic = New-AzNetworkInterface `
            -Name $webNicName `
            -ResourceGroupName $resourceGroupName `
            -Location $location `
            -SubnetId $webSubnetObj.Id `
            -NetworkSecurityGroupId $webNsg.Id
        Write-Host "✅ Web server NIC created"
    } else {
        Write-Host "ℹ️ Web server NIC already exists"
    }

    # Jumpbox NIC
    $jumpboxNicName = "${jumpboxVmName}-nic"
    $jumpboxNic = Get-AzNetworkInterface -Name $jumpboxNicName -ResourceGroupName $resourceGroupName -ErrorAction SilentlyContinue
    if (-not $jumpboxNic) {
        $mngSubnetObj = Get-AzVirtualNetworkSubnetConfig -Name $mngSubnetName -VirtualNetwork $virtualNetwork
        $jumpboxNic = New-AzNetworkInterface `
            -Name $jumpboxNicName `
            -ResourceGroupName $resourceGroupName `
            -Location $location `
            -SubnetId $mngSubnetObj.Id `
            -NetworkSecurityGroupId $mngNsg.Id
        Write-Host "✅ Jumpbox NIC created"
    } else {
        Write-Host "ℹ️ Jumpbox NIC already exists"
    }

    Write-Host "Creating a web server VM ..."
    $webVm = Get-AzVM -ResourceGroupName $resourceGroupName -Name $webVmName -ErrorAction SilentlyContinue
    if (-not $webVm) {
        # Create web server VM using explicit method
        $securePassword = ConvertTo-SecureString "TempPassword123!" -AsPlainText -Force
        $credential = New-Object System.Management.Automation.PSCredential ("azureuser", $securePassword)
        
        $webVmConfig = New-AzVMConfig -VMName $webVmName -VMSize $vmSize
        $webVmConfig = Set-AzVMOperatingSystem -VM $webVmConfig -Linux -ComputerName $webVmName -Credential $credential -DisablePasswordAuthentication
        $webVmConfig = Add-AzVMNetworkInterface -VM $webVmConfig -Id $webNic.Id
        $webVmConfig = Set-AzVMSourceImage -VM $webVmConfig -PublisherName "Canonical" -Offer "0001-com-ubuntu-server-jammy" -Skus "22_04-lts-gen2" -Version "latest"
        $webVmConfig = Add-AzVMSshPublicKey -VM $webVmConfig -KeyData $sshKeyPublicKey -Path "/home/azureuser/.ssh/authorized_keys"
        
        New-AzVM -ResourceGroupName $resourceGroupName -Location $location -VM $webVmConfig
        Write-Host "✅ Web server VM created"
        
        # Install application extension
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
        Write-Host "✅ Web application installed"
    } else {
        Write-Host "ℹ️ Web server VM already exists"
    }

    Write-Host "Creating a public IP with Standard SKU..."
    $publicIP = Get-AzPublicIpAddress -Name $jumpboxVmName -ResourceGroupName $resourceGroupName -ErrorAction SilentlyContinue
    if (-not $publicIP) {
        $publicIP = New-AzPublicIpAddress `
            -Name $jumpboxVmName `
            -ResourceGroupName $resourceGroupName `
            -Location $location `
            -Sku Standard `
            -AllocationMethod Static `
            -DomainNameLabel $dnsLabel
        Write-Host "✅ Public IP created"
    } else {
        Write-Host "ℹ️ Public IP already exists"
    }

    # Associate Public IP with Jumpbox NIC
    Write-Host "Associating Public IP with Jumpbox NIC..."
    $jumpboxNic.IpConfigurations[0].PublicIpAddress = $publicIP
    $jumpboxNic | Set-AzNetworkInterface
    Write-Host "✅ Public IP associated with Jumpbox NIC"

    Write-Host "Creating a management VM ..."
    $jumpboxVm = Get-AzVM -ResourceGroupName $resourceGroupName -Name $jumpboxVmName -ErrorAction SilentlyContinue
    if (-not $jumpboxVm) {
        # Create jumpbox VM using explicit method
        $securePassword = ConvertTo-SecureString "TempPassword123!" -AsPlainText -Force
        $credential = New-Object System.Management.Automation.PSCredential ("azureuser", $securePassword)
        
        $jumpboxVmConfig = New-AzVMConfig -VMName $jumpboxVmName -VMSize $vmSize
        $jumpboxVmConfig = Set-AzVMOperatingSystem -VM $jumpboxVmConfig -Linux -ComputerName $jumpboxVmName -Credential $credential -DisablePasswordAuthentication
        $jumpboxVmConfig = Add-AzVMNetworkInterface -VM $jumpboxVmConfig -Id $jumpboxNic.Id
        $jumpboxVmConfig = Set-AzVMSourceImage -VM $jumpboxVmConfig -PublisherName "Canonical" -Offer "0001-com-ubuntu-server-jammy" -Skus "22_04-lts-gen2" -Version "latest"
        $jumpboxVmConfig = Add-AzVMSshPublicKey -VM $jumpboxVmConfig -KeyData $sshKeyPublicKey -Path "/home/azureuser/.ssh/authorized_keys"
        
        New-AzVM -ResourceGroupName $resourceGroupName -Location $location -VM $jumpboxVmConfig
        Write-Host "✅ Management VM created"
    } else {
        Write-Host "ℹ️ Management VM already exists"
    }

    # Wait for VMs to be fully provisioned and auto-registered in DNS
    Write-Host "Waiting for VMs to be provisioned and auto-registered in DNS (120 seconds)..."
    Start-Sleep -Seconds 120

    # Wait for web server A record to be auto-registered - CRITICAL: CNAME depends on this
    Write-Host "Checking for web server A record auto-registration..."
    $webServerARecord = $null
    $maxAttempts = 15
    $attempt = 1
    
    while (-not $webServerARecord -and $attempt -le $maxAttempts) {
        Write-Host "Attempt $attempt to find A record for $webVmName..."
        $webServerARecord = Get-AzPrivateDnsRecordSet -ResourceGroupName $resourceGroupName -ZoneName $privateDnsZoneName -RecordType A -Name $webVmName -ErrorAction SilentlyContinue
        if (-not $webServerARecord) {
            Write-Host "A record not found yet, waiting 20 seconds..."
            Start-Sleep -Seconds 20
            $attempt++
        }
    }

    if (-not $webServerARecord) {
        throw "❌ Web server A record not found after $maxAttempts attempts. CNAME cannot be created without A record. Check VM provisioning and DNS auto-registration."
    }

    Write-Host "✅ Web server A record found: $webVmName.$privateDnsZoneName -> $($webServerARecord.Records[0].Ipv4Address)"

    # Create CNAME record - ONLY if A record exists
    Write-Host "Creating CNAME record: todo -> $webVmName.$privateDnsZoneName"
    $cnameRecord = Get-AzPrivateDnsRecordSet -ResourceGroupName $resourceGroupName -ZoneName $privateDnsZoneName -RecordType CNAME -Name "todo" -ErrorAction SilentlyContinue

    if ($cnameRecord) {
        Write-Host "ℹ️ CNAME record already exists. Updating..."
        # Remove existing CNAME records
        $cnameRecord.Records.Clear()
        # Add new CNAME record
        Add-AzPrivateDnsRecordConfig -RecordSet $cnameRecord -Cname "$webVmName.$privateDnsZoneName"
        Set-AzPrivateDnsRecordSet -RecordSet $cnameRecord
    } else {
        Write-Host "Creating new CNAME record..."
        
        # Create empty record set
        $recordSet = New-AzPrivateDnsRecordSet `
            -ResourceGroupName $resourceGroupName `
            -ZoneName $privateDnsZoneName `
            -Name "todo" `
            -RecordType "CNAME" `
            -Ttl 3600
        
        # Add CNAME record to the record set
        Add-AzPrivateDnsRecordConfig -RecordSet $recordSet -Cname "$webVmName.$privateDnsZoneName"
        
        # Save the record set
        Set-AzPrivateDnsRecordSet -RecordSet $recordSet
    }

    # Verify the CNAME record was created
    $verifyCname = Get-AzPrivateDnsRecordSet -ResourceGroupName $resourceGroupName -ZoneName $privateDnsZoneName -RecordType CNAME -Name "todo" -ErrorAction SilentlyContinue
    if ($verifyCname -and $verifyCname.Records) {
        Write-Host "✅ CNAME record successfully created: todo.$privateDnsZoneName -> $($verifyCname.Records[0].Cname)"
    } else {
        throw "❌ CNAME record creation failed"
    }

    Write-Host "`n🎉 Private DNS configuration completed successfully!"
    Write-Host "📋 DNS Records created:"
    Write-Host "  - Private DNS Zone: $privateDnsZoneName"
    Write-Host "  - CNAME record: todo.$privateDnsZoneName -> $webVmName.$privateDnsZoneName"
    Write-Host "  - Virtual Network Link: $vnetLinkName (with auto-registration)"

    # Display connection information
    Write-Host "`n🔗 Connection Information:"
    Write-Host "  - Web application URL: http://todo.$privateDnsZoneName:8080/"
    Write-Host "  - Jumpbox public IP: $($publicIP.IpAddress)"
    Write-Host "  - SSH to jumpbox: ssh azureuser@$($publicIP.IpAddress)"
    Write-Host "  - From jumpbox, test web app: curl http://todo.$privateDnsZoneName:8080/"

}
catch {
    Write-Error "❌ Deployment failed: $($_.Exception.Message)"
    exit 1
}