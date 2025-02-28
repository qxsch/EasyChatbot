param (
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,

    [string]$resourceSuffix = $null,

    [string]$location = $null,
    [string]$aiLocation = $null,

    [string]$webAppName = $null,
    [string]$sku = $null,
    [string]$workerSize = $null,

    [string]$FilesDir = "",

    [string]$azureSearchName = $null,
    [string]$azureSearchSku = $null,
    [int]$azureSearchReplicaCount = 0,
    [int]$azureSearchPartitionCount = 0,

    [string]$azureOpenAiName = $null,
    [string]$gpt4oDeploymentName = $null,
    [int]$gpt4oDeploymentCapacity = 0,
    [string]$adaDeploymentName = $null,
    [int]$adaDeploymentCapacity = 0,

    [string]$entraClientId = '',
    [SecureString]$entraClientSecret = $null,

    [switch]$skipIacDeployment,
    [switch]$skipPdfUploadToStorage,
    [switch]$skipAzureSearchConfiguration,
    [switch]$doNotCleanUp
)


$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
$botRoot = Split-Path -Parent $scriptPath

if($FilesDir -eq "") {
    $FilesDir = (Join-Path $botRoot "pdf_documents")
}
if(-not (Test-Path $FilesDir -PathType Container)) {
    throw "FilesDir must be a directory"
}
# check if the required files exist
if($entraClientId -eq '') {
    $requiredFiles = @( "users.json", "roles.json", "system-prompt.md" )
}
else {
    $requiredFiles = @( "roles.json", "system-prompt.md" ) 
}
foreach($fname in $requiredFiles) {
    if(-not (Test-Path (Join-Path $botRoot $fname) -PathType Leaf)) {
        throw "The file '$fname' does not exist in the directory '$botRoot'"
    }
}

# check if there are any other Cognitive Services accounts in the subscription
if((Get-AzCognitiveServicesAccount | Where-Object { $_.AccountType -eq "OpenAi" -and ( $_.ResourceGroupName -ne $ResourceGroupName -and $_.AccountName -like "openai*") }).Count -gt 0) {
    Write-Warning "There are multiple OpenAI Cognitive Services accounts in the subscription. This might lead to failing deployments. Please make sure that the deployment capacities are set correctly!"
    if(($gpt4oDeploymentCapacity -le 0) -or (-eq $adaDeploymentCapacity -le 0)) {
        throw "There are multiple OpenAI Cognitive Services accounts in the subscription. Please set -gpt4oDeploymentCapacity and -adaDeploymentCapacity!"
    }
}

# run the bicep deployment
if(-not $skipIacDeployment) {
    $roleCleanupScript = Join-Path $scriptPath "removeOrphanedRoleAssignments.ps1"
    & "$roleCleanupScript" -resourceGroupName $ResourceGroupName -ErrorAction Stop


    Write-Host ( "Deploying the Azure resources to Resource Group $ResourceGroupName (Subscription: " + ((Get-AzContext).Subscription.Id) + ")" )
    $params = @{
        TemplateFile = (Join-Path $scriptPath "deployment.bicep")
        ResourceGroupName = $ResourceGroupName
    }
    if(-not($null -eq $resourceSuffix -or $resourceSuffix -eq "")) {
        $params["resourceSuffix"] = $resourceSuffix
    }
    if(-not($null -eq $location -or $location -eq "")) {
        $params["location"] = $location
    }
    if(-not($null -eq $webAppName -or $webAppName -eq "")) {
        $params["webAppName"] = $webAppName
    }
    if(-not($null -eq $sku -or $sku -eq "")) {
        Write-Host "Setting sku to $sku"
        $params["sku"] = $sku
    }
    if(-not($null -eq $workerSize -or $workerSize -eq "")) {
        $params["workerSize"] = $workerSize
    }
    if(-not($null -eq $azureSearchName -or $azureSearchName -eq "")) {
        $params["azureSearchName"] = $azureSearchName
    }
    if(-not($null -eq $azureSearchSku -or $azureSearchSku -eq "")) {
        $params["azureSearchSku"] = $azureSearchSku
    }
    if($azureSearchReplicaCount -gt 0) {
        $params["azureSearchReplicaCount"] = $azureSearchReplicaCount
    }
    if($azureSearchPartitionCount -gt 0) {
        $params["azureSearchPartitionCount"] = $azureSearchPartitionCount
    }
    if(-not($null -eq $azureOpenAiName -or $azureOpenAiName -eq "")) {
        $params["azureOpenAiName"] = $azureOpenAiName
    }
    if(-not($null -eq $aiLocation -or $aiLocation -eq "")) {
        $params["aiLocation"] = $aiLocation
    }
    if(-not($null -eq $gpt4oDeploymentName -or $gpt4oDeploymentName -eq "")) {
        $params["gpt4oDeploymentName"] = $gpt4oDeploymentName
    }
    if($gpt4oDeploymentCapacity -gt 0) {
        $params["gpt4oDeploymentCapacity"] = $gpt4oDeploymentCapacity
    }
    if(-not($null -eq $adaDeploymentName -or $adaDeploymentName -eq "")) {
        $params["adaDeploymentName"] = $adaDeploymentName
    }
    if($adaDeploymentCapacity -gt 0) {
        $params["adaDeploymentCapacity"] = $adaDeploymentCapacity
    }
    if($entraClientId -ne '') {
        $params["entraClientId"] = $entraClientId
        if($entraClientSecret -is [SecureString]) {
            $params["entraClientSecret"] = $entraClientSecret
        }
    }

    $evx = @()
    $deployment = New-AzResourceGroupDeployment @params -Name "chatbot"  -ErrorAction Continue -ErrorVariable +evx
    if($null -eq $deployment) {
        foreach($ev in ($evx | Where-Object { $_.Exception.Message.Contains('soft-deleted') })) {
            Write-Host -ForegroundColor Yellow "Soft deleted resource found:`n$($ev.Exception.Message)"
        }
        throw "Deployment failed"
    }
    Write-Host "Azure resource group deployment completed"
    Write-Host ( "  - Web App Name:         " + $deployment.Outputs.webAppName.Value )
    Write-Host ( "  - Web App URL:          https://" + $deployment.Outputs.webAppUrl.Value )
    Write-Host ( "  - Azure Search Name:    " + $deployment.Outputs.azureSearchName.Value )
    Write-Host ( "  - Storage Account Name: " + $deployment.Outputs.storageAccountName.Value )
}
else {
    Write-Host -ForegroundColor Yellow "Skipping the deployment of the Azure resources"
}

# set the value, in case it was not provided
if($azureSearchName -eq $null -or $azureSearchName -eq "") {
    $azureSearchName = $deployment.Outputs.azureSearchName.Value
}

# getting the storage account and openai account
$storAcc = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName | Where-Object { $_.StorageAccountName -like "storage*" }
$azOAI = Get-AzCognitiveServicesAccount -ResourceGroupName $ResourceGroupName | Where-Object { $_.AccountType -eq "OpenAi" -and $_.AccountName -like "openai*" }
$azSrc = Get-AzSearchService -ResourceGroupName $ResourceGroupName | Where-Object { $_.Name -like "search-*" }



if(-not $skipPdfUploadToStorage) {
    Write-Host "Uploading pdf files to the storage account"
    Get-ChildItem $FilesDir -Recurse -Filter "*.pdf" | ForEach-Object {
        $file = $_
        $blobName = $file.FullName.Substring($FilesDir.Length + 1)
        if($null -eq (Get-AzStorageBlob -Container "documents" -Blob $blobName -Context $storAcc.Context -ErrorAction SilentlyContinue -WarningAction Ignore)) {
            Write-Host "  - Uploading $blobName"
            Set-AzStorageBlobContent -File $file.FullName -Container "documents" -Blob $blobName -Context $storAcc.Context -Force | Out-Null
        }
    }
}
else {
    Write-Host -ForegroundColor Yellow "Skipping upload of pdf files to storage account"
}


# configuring azure search
if(-not $skipAzureSearchConfiguration) {
    Write-Host "Configuring Azure Search"
    # resolving the ada deployment name
    $adaDeploymentName = ""
    foreach($x in (Get-AzCognitiveServicesAccountDeployment -ResourceGroupName $ResourceGroupName -AccountName $azOAI.AccountName)) {
        if($x.Properties.Model.Name -eq "text-embedding-ada-002") {
            $adaDeploymentName = $x.Name
            break
        }
    }
    if($adaDeploymentName -eq "") {
        throw "Could not find the deployment name for the model 'text-embedding-ada-002'"
    }

    $azureSearchDeployScript = Join-Path $scriptPath "azure_search" "deploy.ps1"
    & "$azureSearchDeployScript" -ResourceGroupName $ResourceGroupName -azureSearchName $azSrc.Name -storageAccountId $storAcc.Id -openAiBaseUrl $azOAI.Properties.Endpoint -adaDeploymentName $adaDeploymentName -ErrorAction Stop

}
else {
    Write-Host -ForegroundColor Yellow "Skipping Azure Search configuration"
}


$webApps = Get-AzWebApp -ResourceGroupName $ResourceGroupName -WarningAction Ignore | Where-Object { $_.Name -like "chat-*" }


# deploying the zip package
Write-Host "Creating the zip package"
$zipPackagePath = Join-Path $scriptPath "chat_bot.zip"
if(Test-Path $zipPackagePath) {
    Remove-Item $zipPackagePath -Force
}
# remove pycache directories
Get-ChildItem $botRoot -Recurse | Where-Object { $_.Name -eq '__pycache__' } | Remove-Item -Recurse -Force
# create the zip package
Get-ChildItem $botRoot | Where-Object { $_.Name -notin @( "iac", "pdf_documents" ) } | Compress-Archive -DestinationPath $zipPackagePath
Write-Host "Publishing the zip package to the web app"
$webApps | ForEach-Object {
    Write-Host ( "  - Publishing to " + $_.Name )
    Publish-AzWebApp -ResourceGroupName $ResourceGroupName -Name $_.Name -ArchivePath $zipPackagePath -Force -ErrorAction Stop | Out-Null
}

if(-not $doNotCleanUp) {
    Write-Host "Cleaning up"
    # clean up the zip package
    Remove-Item -Path $zipPackagePath -Force | Out-Null
}


Write-Host "Deployment completed - Sleeping for 10 seconds before getting the URL"
Start-Sleep -Seconds 10

# Write-Host -ForegroundColor Green ( "URL:  https://" + $deployment.Outputs.webAppUrl.Value )
$webApps | ForEach-Object {
    Write-Host -ForegroundColor Green ( "URL:  https://" + $_.DefaultHostName )
}
