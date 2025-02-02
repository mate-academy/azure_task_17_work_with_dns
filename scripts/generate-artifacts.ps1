param(
    [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
    [string]$ArtifactsStorageAccountName='matestorage123'
)

# default script values
$rgName = "mate-azure-task-17"
$taskName = "task17"

$containerName = "task-artifacts"
$resourcesTemplateName = "exported-template.json"
$tempFolderPath = "$PWD/temp"
$artifactsConfigPath = "$PWD/artifacts.json"

# initial validation
Write-Output "Running initial validation"
$context = Get-AzContext  
if ($context)   
{  
    Write-Output "Azure Powershell module is installed, account is connected."  
} else {  
    throw "Please log in to Azure using Azure Powershell module (run Connect-AzAccount)"
}  

Write-Output "Checking if storage account exists"
$storageAccount = (Get-AzStorageAccount -ErrorAction SilentlyContinue | Where-Object -Property 'StorageAccountName' -EQ -Value $ArtifactsStorageAccountName )
if ($storageAccount) {
    Write-Output "Storage account found"
} else { 
    throw "Unable to find storage account $ArtifactsStorageAccountName . Please make sure, that you specified the correct name of the storage account for the artifacts and that it is present in your Azure subscription"
}

Write-Output "Checking if artifacts storage container exists" 
$artifactContainer = Get-AzStorageContainer -Name $containerName -Context $storageAccount.Context -ErrorAction SilentlyContinue
if ($artifactContainer) { 
    Write-Output "Storage container for artifacts found!" 
} else { 
    throw "Unable to find a storage container $containerName in the storage account $ArtifactsStorageAccountName, please make sure that it's created"
}

# generation of artifacts
Write-Output "Generating artifacts"

Write-Output "Checking if temp folder exists"
if (-not (Test-Path "$tempFolderPath")) { 
    Write-Output "Temp folder does not exist, creating..."
    New-Item -ItemType Directory -Path $tempFolderPath
}

Write-Output "Exporting resources template"
Export-AzResourceGroup -ResourceGroupName $rgName -Path "$tempFolderPath/$resourcesTemplateName" -Force

Write-Output "Uploading resources template"
$ResourcesTemplateBlob = @{
    File             = "$tempFolderPath/$resourcesTemplateName"
    Container        = $containerName
    Blob             = "$taskName/$resourcesTemplateName"
    Context          = $storageAccount.Context
    StandardBlobTier = 'Hot'
}
$blob = Set-AzStorageBlobContent @ResourcesTemplateBlob -Force

Write-Output "Generating a SAS token for the template artifact"
$date = Get-Date
$date = $date.AddDays(30) 
$resourcesTemplateSaSToken = New-AzStorageBlobSASToken -Container $containerName -Blob "$taskName/$resourcesTemplateName" -Permission r -ExpiryTime $date -Context $storageAccount.Context
$resourcesTemplateURL = "$($blob.ICloudBlob.uri.AbsoluteUri)?$resourcesTemplateSaSToken"


# updating artifacts config
Write-Output "Updating artifacts config"
$artifactsConfig = @{
    resourcesTemplate = "$resourcesTemplateURL"
}
$artifactsConfig | ConvertTo-Json | Out-File -FilePath $artifactsConfigPath -Force