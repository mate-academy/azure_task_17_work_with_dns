param(
    [Parameter(Mandatory=$false, ValueFromPipeline=$true)]
    [bool]$DownloadArtifacts=$true
)


# default script values 
$taskName = "task17"

$artifactsConfigPath = "$PWD/artifacts.json"
$resourcesTemplateName = "exported-template.json"
$tempFolderPath = "$PWD/temp"

if ($DownloadArtifacts) { 
    Write-Output "Reading config" 
    $artifactsConfig = Get-Content -Path $artifactsConfigPath | ConvertFrom-Json 

    Write-Output "Checking if temp folder exists"
    if (-not (Test-Path "$tempFolderPath")) { 
        Write-Output "Temp folder does not exist, creating..."
        New-Item -ItemType Directory -Path $tempFolderPath
    }

    Write-Output "Downloading artifacts"

    if (-not $artifactsConfig.resourcesTemplate) { 
        throw "Artifact config value 'resourcesTemplate' is empty! Please make sure that you executed the script 'scripts/generate-artifacts.ps1', and commited your changes"
    } 
    Invoke-WebRequest -Uri $artifactsConfig.resourcesTemplate -OutFile "$tempFolderPath/$resourcesTemplateName" -UseBasicParsing

}

Write-Output "Validating artifacts"
$TemplateFileText = [System.IO.File]::ReadAllText("$tempFolderPath/$resourcesTemplateName")
$TemplateObject = ConvertFrom-Json $TemplateFileText -AsHashtable

$virtualNetwork = ( $TemplateObject.resources | Where-Object -Property type -EQ "Microsoft.Network/virtualNetworks" )
if ($virtualNetwork ) {
    if ($virtualNetwork.name.Count -eq 1) { 
        Write-Output "`u{2705} Checked if virtual network exists - OK."
    }  else { 
        Write-Output `u{1F914}
        throw "More than one virtual network resource was found in the task resource group. Please make sure that your script deploys only 1 virtual network, and try again."
    }
} else {
    Write-Output `u{1F914}
    throw "Unable to find virtual network in the task resource group. Please make sure that your script creates a virtual network and try again."
}

$virtualNetworkName = $virtualNetwork.name.Replace("[parameters('virtualNetworks_", "").Replace("_name')]", "")
if ($virtualNetworkName -eq "todoapp") { 
    Write-Output "`u{2705} Checked the virtual network name - OK."
} else { 
    Write-Output `u{1F914}
    throw "Unable to verify the virtual network name. Please make sure that your script creates a virtual network called 'todoapp' and try again."
}

if ($virtualNetwork.properties.addressSpace.addressPrefixes -eq "10.20.30.0/24") { 
    Write-Output "`u{2705} Checked the virtual network address space - OK."
} else { 
    Write-Output `u{1F914}
    throw "Unable to verify the virtual network address space. Please make sure that your script creates a virtual network with address space, described in the task, and try again."
}

$subnets = $virtualNetwork.properties.subnets
if ($subnets) {
    if ($subnets.name.Count -eq 2) { 
        Write-Output "`u{2705} Checked if 2 subnets exist - OK."
    }  else { 
        Write-Output `u{1F914}
        throw "Wrong number of subnets was found in the virtual network. Please make sure that your script deploys 2 subnets, and try again."
    }
} else {
    Write-Output `u{1F914}
    throw "Unable to find subnets in the virtual network. Please make sure that your script creates 2 subnets and try again."
}

$requiredSubnets = @("webservers", "management") 
foreach ($requiredSubnet in $requiredSubnets) { 
    $artifactSubnet = $subnets | Where-Object {$_.name -eq $requiredSubnet} 
    if ($artifactSubnet) { 
        if ($artifactSubnet.properties.addressPrefix.EndsWith("/26")) { 
            Write-Output "`u{2705} Checked $requiredSubnet subnet - OK."
        } else {
            Write-Output `u{1F914}
            throw "Unable to verify subnet $requiredSubnet address space. Please make sure that you are creating a subnet, which can fit 50 hosts and uses address space effectively (confider creating /26 subnet)."        
        }

        $artifactNsg = $artifactSubnet.properties.networkSecurityGroup 
        if ($artifactNsg) { 
            if ($artifactNsg.id.Contains($requiredSubnet)) { 
                Write-Output "`u{2705} Checked if $requiredSubnet subnet has NSG attached - OK."
            } else  {
                Write-Output `u{1F914}
                throw "Unable to verify subnet '$requiredSubnet' in the virtual network. Please make sure that all your subnets have their own network security groups, that NSGs attached to corresponding subnets and try again."
            }
        } else { 
            Write-Output `u{1F914}
            throw "Unable to verify subnet '$requiredSubnet' in the virtual network. Please make sure that all your subnets have network security group attached and try again."
        }

    } else { 
        Write-Output `u{1F914}
        throw "Unable to verify subnet '$requiredSubnet' in the virtual network. Please make sure that your script creates 3 subnets and try again."
    }
}

$webserversNSG = ( $TemplateObject.resources | Where-Object -Property type -EQ "Microsoft.Network/networkSecurityGroups" | Where-Object {$_.name.Contains("webservers")})
if ($webserversNSG.properties.securityRules.Count -eq 1) { 
    Write-Output "`u{2705} Checked if webservers NSG has only 1 rule - OK."
} else { 
    Write-Output `u{1F914}
    throw "Unable to verify webservers NSG. Please make sure that it has only 1 rule and try again."
}
$webRule = $webserversNSG.properties.securityRules | Where-Object {$_.properties.sourcePortRange -eq "*" -and $_.properties.access -eq "Allow" -and $_.properties.protocol -eq "TCP" -and $_.properties.direction -eq "Inbound" -and $_.properties.destinationPortRanges.Contains("80") -and $_.properties.destinationPortRanges.Contains("443")}
if ($webRule) { 
    Write-Output "`u{2705} Checked if webservers NSG allows HTTP traffic - OK."
} else { 
    Write-Output `u{1F914}
    throw "Unable to verify webservers NSG. Please make sure that it has only 1 rule, which allows inbound traffic on TCP ports 80 and 443 from any source port and IP address and try again."
}
 
$managementNSG = ( $TemplateObject.resources | Where-Object -Property type -EQ "Microsoft.Network/networkSecurityGroups" | Where-Object {$_.name.Contains("management")})
if ($managementNSG.properties.securityRules.Count -eq 1) { 
    Write-Output "`u{2705} Checked if management NSG has only 1 rule - OK."
} else { 
    Write-Output `u{1F914}
    throw "Unable to verify management NSG. Please make sure that it has only 1 rule and try again."
}
$sshRule = $managementNSG.properties.securityRules | Where-Object {$_.properties.sourcePortRange -eq "*" -and $_.properties.access -eq "Allow" -and $_.properties.protocol -eq "TCP" -and $_.properties.direction -eq "Inbound" -and $_.properties.destinationPortRange -eq "22"}
if ($sshRule) { 
    Write-Output "`u{2705} Checked if management NSG allows SSH traffic - OK."
} else { 
    Write-Output `u{1F914}
    throw "Unable to verify management NSG. Please make sure that it has only 1 rule, which allows inbound traffic on TCP port 22 from any source port and IP address and try again."
}

$dnsZone = ( $TemplateObject.resources | Where-Object -Property type -EQ "Microsoft.Network/privateDnsZones" | Where-Object {$_.name.Contains("privateDnsZones_or_nottodo_name")})
if ($dnsZone) { 
    Write-Output "`u{2705} Checked if DNS zone or.nottodo is created - OK."
} else {
    Write-Output `u{1F914}
    throw "Unable to verify Private DNS zone 'or.nottodo'. Please make sure that it is created and try again."
}

$dnsZoneLink = ( $TemplateObject.resources | Where-Object -Property type -EQ "Microsoft.Network/privateDnsZones/virtualNetworkLinks")
if ($dnsZoneLink) {
    if ($dnsZoneLink.name.Count -eq 1) { 
        Write-Output "`u{2705} Checked virtual network link for DNS zone - OK."
    }  else { 
        Write-Output `u{1F914}
        throw "More than one virtual network link for DNS zone was found in the task resource group. Please make sure that your script deploys only 1 virtual network link for DNS zone, and try again."
    }
} else {
    Write-Output `u{1F914}
    throw "Unable to find virtual network link for DNS zone in the task resource group. Please make sure that your script creates a virtual network link for DNS zone and try again."
}

if ($dnsZoneLink.properties.registrationEnabled) { 
    Write-Output "`u{2705} Checked virtual network link for DNS zone has auto-registration endbles - OK."
} else { 
    Write-Output `u{1F914}
    throw "Please make sure that your private DNS zone link for virtual network has auto-registration enabled and try again."
}

$cname = ( $TemplateObject.resources | Where-Object -Property type -EQ "Microsoft.Network/privateDnsZones/CNAME" | Where-Object {$_.name.Contains("'/todo'")})
if ($cname) { 
    if ($cname.properties.cnameRecord.cname -eq 'webserver.or.nottodo') { 
        Write-Output "`u{2705} Checked CNAME DNS record - OK."
    } else { 
        Write-Output `u{1F914}
        throw "Please make sure that you have a CNAME record for the 'todo' host points to the auto-registered DNS name of the webserver virtual machine ('webserver.or.nottodo') and try again."
    }
} else { 
    Write-Output `u{1F914}
    throw "Please make sure that you have a CNAME record for the 'todo' host created in your private DNS zone and try again."
}

Write-Output ""
Write-Output "`u{1F973} Congratulations! All tests passed!"