param(
    [Parameter(Mandatory = $true)]
    [string]$resourceGroupName,
    [Parameter(Mandatory = $true)]
    [string]$azureSearchName,

    [ValidateLength(10, 600)]
    [string]$storageAccountId,
    [ValidateLength(10, 600)]
    [string]$openAiBaseUrl,
    [string]$adaDeploymentName = "text-embedding-ada-002",
    [switch]$debugRenderedJson
)

Import-Module Az.Search

# get the path of this script
$scriptPath = Split-Path -parent $MyInvocation.MyCommand.Definition

$azureSearchEndpoint = ( 'https://' + $azureSearchName + '.search.windows.net' )
$azureSearchKey = (Get-AzSearchAdminKeyPair -ResourceGroupName $resourceGroupName -ServiceName $azureSearchName -ErrorAction Stop -WarningAction Ignore).Primary



$datasource = Get-Content (Join-Path $scriptPath "documents-datasource.json") | ConvertFrom-Json -AsHashtable -Depth 100
$datasource["credentials"]["connectionString"] = ( 'ResourceId=' + $storageAccountId + ';' )
if($debugRenderedJson) {
    Write-Host "Data Source JSON:"
    Write-Host -ForegroundColor Cyan ($datasource | ConvertTo-Json -Depth 100)
}
# deploy the data source
try {
    Write-Host -ForegroundColor Yellow "Data Source 'documents-datasource' already exists for Azure Search"
    Invoke-RestMethod -Method Get -Uri ( $azureSearchEndpoint + "/datasources('" + $datasource["name"] + "')?api-version=2024-09-01-preview" ) -Headers @{ "api-key" = $azureSearchKey } -ErrorAction Stop | Out-Null
}
catch {
    Write-Host -ForegroundColor Green "Creating Data Source 'documents-datasource' for Azure Search"
    Invoke-RestMethod -Method Post -Uri ( $azureSearchEndpoint + "/datasources?api-version=2024-09-01-preview" ) -Headers @{ "api-key" = $azureSearchKey } -Body ( $datasource | ConvertTo-Json -Depth 100 ) -ContentType "application/json"
}



$index = Get-Content (Join-Path $scriptPath "documents-index.json") | ConvertFrom-Json -AsHashtable -Depth 100
$index["vectorSearch"]["vectorizers"] | Where-Object { $_["kind"] -eq "azureOpenAI" } | ForEach-Object {
    $_["azureOpenAIParameters"]["resourceUri"] = $openAiBaseUrl
    $_["azureOpenAIParameters"]["deploymentId"] = $adaDeploymentName
}
if($debugRenderedJson) {
    Write-Host "Index JSON:"
    Write-Host -ForegroundColor Cyan ($index | ConvertTo-Json -Depth 100)
}
try {
    Write-Host -ForegroundColor Yellow "Index 'documents-index' already exists for Azure Search"
    Invoke-RestMethod -Method Get -Uri ( $azureSearchEndpoint + "/indexes('" + $index["name"] + "')?api-version=2024-09-01-preview" ) -Headers @{ "api-key" = $azureSearchKey } -ErrorAction Stop | Out-Null
}
catch {
    Write-Host -ForegroundColor Green "Creating Index 'documents-index' for Azure Search"
    Invoke-RestMethod -Method Post -Uri ( $azureSearchEndpoint + "/indexes?api-version=2024-09-01-preview" ) -Headers @{ "api-key" = $azureSearchKey } -Body ( $index | ConvertTo-Json -Depth 100 ) -ContentType "application/json"
}



$skillset = Get-Content (Join-Path $scriptPath "documents-skillset.json") | ConvertFrom-Json -AsHashtable -Depth 100
$skillset["skills"] | Where-Object { $_["@odata.type"] -eq "#Microsoft.Skills.Text.AzureOpenAIEmbeddingSkill" } | ForEach-Object {
    $_["resourceUri"] = $openAiBaseUrl
    $_["deploymentId"] = $adaDeploymentName
}
if($debugRenderedJson) {
    Write-Host "Skillset JSON:"
    Write-Host -ForegroundColor Cyan ($skillset | ConvertTo-Json -Depth 100)
}
try {
    Write-Host -ForegroundColor Yellow "Skillset 'documents-skillset' already exists for Azure Search"
    Invoke-RestMethod -Method Get -Uri ( $azureSearchEndpoint + "/skillsets('" + $skillset["name"] + "')?api-version=2024-09-01-preview" ) -Headers @{ "api-key" = $azureSearchKey } -ErrorAction Stop | Out-Null
}
catch {
    Write-Host -ForegroundColor Green "Creating Skillset 'documents-skillset' for Azure Search"
    Invoke-RestMethod -Method Post -Uri ( $azureSearchEndpoint + "/skillsets?api-version=2024-09-01-preview" ) -Headers @{ "api-key" = $azureSearchKey } -Body ( $skillset | ConvertTo-Json -Depth 100 ) -ContentType "application/json"
}



$indexer = Get-Content (Join-Path $scriptPath "documents-indexer.json") | ConvertFrom-Json -AsHashtable -Depth 100
if($debugRenderedJson) {
    Write-Host "Indexer JSON:"
    Write-Host -ForegroundColor Cyan ($indexer | ConvertTo-Json -Depth 100)
}
try {
    Write-Host -ForegroundColor Yellow "Indexer 'documents-indexer' already exists for Azure Search"
    Invoke-RestMethod -Method Get -Uri ( $azureSearchEndpoint + "/indexers('" + $indexer["name"] + "')?api-version=2024-09-01-preview" ) -Headers @{ "api-key" = $azureSearchKey } -ErrorAction Stop | Out-Null
}
catch {
    Write-Host -ForegroundColor Green "Creating Indexer 'documents-indexer' for Azure Search  (this may take up to 15 minutes)"
    $tries = 0
    while($true) {
        try {
            Write-Host " - Running attempt $tries"
            Invoke-RestMethod -Method Post -Uri ( $azureSearchEndpoint + "/indexers?api-version=2024-09-01-preview" ) -Headers @{ "api-key" = $azureSearchKey } -Body ( $indexer | ConvertTo-Json -Depth 100 ) -ContentType "application/json"
            break
        }
        catch {
            if($tries -gt 15) {
                Write-Host -ForegroundColor Red " - Failed to create the indexer after 10 attempts"
                throw $_
            }    
            elseif($_.Exception.Message -like "*Unable to retrieve blob container for account*") {
                Write-Host -ForegroundColor Yellow " - Entra ID roles are not yet propagated. Waiting 1 minute before retrying"
                Start-Sleep -Seconds 60
            }
            else {
                throw $_
            }
        }
        $tries++
    }
}
