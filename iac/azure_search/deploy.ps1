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
    [switch]$debugRenderedJson,
    [switch]$updateAll
)

Import-Module Az.Search

# get the path of this script
$scriptPath = Split-Path -parent $MyInvocation.MyCommand.Definition


class AzureSearchDeployment {
    hidden [string] $azureSearchEndpoint
    hidden [string] $azureSearchKey
    hidden [bool] $debugRenderedJson = $false

    AzureSearchDeployment([ string ]$resourceGroupName, [ string ]$azureSearchName) {
        $this.azureSearchEndpoint = ( 'https://' + $azureSearchName + '.search.windows.net' )
        $this.azureSearchKey = (Get-AzSearchAdminKeyPair -ResourceGroupName $resourceGroupName -ServiceName $azureSearchName -ErrorAction Stop -WarningAction Ignore).Primary
    }

    [void] SetRenderDebugJson([bool] $debugRenderedJson) {
        $this.debugRenderedJson = $debugRenderedJson
    }

    [bool] GetRenderDebugJson() {
        return $this.debugRenderedJson
    }

    [void] RenderDebugJson([hashtable] $json, [string] $name) {
        if($this.debugRenderedJson) {
            Write-Host "$name JSON:"
            Write-Host -ForegroundColor Cyan ($json | ConvertTo-Json -Depth 100)
        }
    }

    [void] CreateDataSource([hashtable] $datasource, [bool]$update = $false) {
        $this.RenderDebugJson($datasource, "Data Source")
        if(-not $datasource.ContainsKey("name")) {
            throw "Data Source must have a 'name' key"
        }
        try {
            Invoke-RestMethod -Method Get -Uri ( $this.azureSearchEndpoint + "/datasources('" + $datasource["name"] + "')?api-version=2024-09-01-preview" ) -Headers @{ "api-key" = $this.azureSearchKey } -ErrorAction Stop | Out-Null
            Write-Host -ForegroundColor Yellow "Data Source '$($datasource["name"])' already exists for Azure Search"
            $exists = $true
        }
        catch {
            $exists = $false
        }
        if(-not $exists) {
            Write-Host -ForegroundColor Green "Creating Data Source '$($datasource["name"])' for Azure Search"
            Invoke-RestMethod -Method Post -Uri ( $this.azureSearchEndpoint + "/datasources?api-version=2024-09-01-preview" ) -Headers @{ "api-key" = $this.azureSearchKey } -Body ( $datasource | ConvertTo-Json -Depth 100 ) -ContentType "application/json" | Out-Null
        }
        elseif($exists -and $update) {
            Write-Host -ForegroundColor Green "Updating Data Source '$($datasource["name"])' for Azure Search"
            Invoke-RestMethod -Method Put -Uri ( $this.azureSearchEndpoint + "/datasources('" + $datasource["name"] + "')?api-version=2024-09-01-preview" ) -Headers @{ "api-key" = $this.azureSearchKey } -Body ( $datasource | ConvertTo-Json -Depth 100 ) -ContentType "application/json" | Out-Null
        }
    }

    [void]CreateIndex([hashtable] $index, [bool]$update = $false) {
        $this.RenderDebugJson($index, "Index")
        if(-not $index.ContainsKey("name")) {
            throw "Index must have a 'name' key"
        }
        try {
            Invoke-RestMethod -Method Get -Uri ( $this.azureSearchEndpoint + "/indexes('" + $index["name"] + "')?api-version=2024-09-01-preview" ) -Headers @{ "api-key" = $this.azureSearchKey } -ErrorAction Stop | Out-Null
            Write-Host -ForegroundColor Yellow "Index '$($index["name"])' already exists for Azure Search"
            $exists = $true
        }
        catch {
            $exists = $false
        }
        if(-not $exists) {
            Write-Host -ForegroundColor Green "Creating Index '$($index["name"])' for Azure Search"
            Invoke-RestMethod -Method Post -Uri ( $this.azureSearchEndpoint + "/indexes?api-version=2024-09-01-preview" ) -Headers @{ "api-key" = $this.azureSearchKey } -Body ( $index | ConvertTo-Json -Depth 100 ) -ContentType "application/json" | Out-Null
        }
        elseif($exists -and $update) {
            Write-Host -ForegroundColor Green "Updating Index '$($index["name"])' for Azure Search"
            Invoke-RestMethod -Method Put -Uri ( $this.azureSearchEndpoint + "/indexes('" + $index["name"] + "')?api-version=2024-09-01-preview" ) -Headers @{ "api-key" = $this.azureSearchKey } -Body ( $index | ConvertTo-Json -Depth 100 ) -ContentType "application/json" | Out-Null
        }
    }

    [void]CreateSkillset([hashtable] $skillset, [bool]$update = $false) {
        $this.RenderDebugJson($skillset, "Skillset")
        if(-not $skillset.ContainsKey("name")) {
            throw "Skillset must have a 'name' key"
        }
        try {
            Invoke-RestMethod -Method Get -Uri ( $this.azureSearchEndpoint + "/skillsets('" + $skillset["name"] + "')?api-version=2024-09-01-preview" ) -Headers @{ "api-key" = $this.azureSearchKey } -ErrorAction Stop | Out-Null
            Write-Host -ForegroundColor Yellow "Skillset '$($skillset["name"])' already exists for Azure Search"
            $exists = $true
        }
        catch {
            $exists = $false
        }
        if(-not $exists) {
            Write-Host -ForegroundColor Green "Creating Skillset '$($skillset["name"])' for Azure Search"
            Invoke-RestMethod -Method Post -Uri ( $this.azureSearchEndpoint + "/skillsets?api-version=2024-09-01-preview" ) -Headers @{ "api-key" = $this.azureSearchKey } -Body ( $skillset | ConvertTo-Json -Depth 100 ) -ContentType "application/json" | Out-Null
        }
        elseif($exists -and $update) {
            Write-Host -ForegroundColor Green "Updating Skillset '$($skillset["name"])' for Azure Search"
            Invoke-RestMethod -Method Put -Uri ( $this.azureSearchEndpoint + "/skillsets('" + $skillset["name"] + "')?api-version=2024-09-01-preview" ) -Headers @{ "api-key" = $this.azureSearchKey } -Body ( $skillset | ConvertTo-Json -Depth 100 ) -ContentType "application/json" | Out-Null
        }
    }

    [void]CreateIndexer([hashtable] $indexer, [bool]$update = $false) {
        $this.RenderDebugJson($indexer, "Indexer")
        if(-not $indexer.ContainsKey("name")) {
            throw "Indexer must have a 'name' key"
        }
        try {
            Invoke-RestMethod -Method Get -Uri ( $this.azureSearchEndpoint + "/indexers('" + $indexer["name"] + "')?api-version=2024-09-01-preview" ) -Headers @{ "api-key" = $this.azureSearchKey } -ErrorAction Stop | Out-Null
            Write-Host -ForegroundColor Yellow "Indexer '$($indexer["name"])' already exists for Azure Search"
            $exists = $true
        }
        catch {
            $exists = $false
        }
        if(-not $exists) {
            Write-Host -ForegroundColor Green "Creating Indexer '$($indexer["name"])' for Azure Search (this may take up to 15 minutes)"
            $tries = 1
            while($true) {
                try {
                    Write-Host " - Running attempt $tries"
                    Invoke-RestMethod -Method Post -Uri ( $this.azureSearchEndpoint + "/indexers?api-version=2024-09-01-preview" ) -Headers @{ "api-key" = $this.azureSearchKey } -Body ( $indexer | ConvertTo-Json -Depth 100 ) -ContentType "application/json" | Out-Null
                    break
                }
                catch {
                    if($tries -gt 15) {
                        Write-Host -ForegroundColor Red " - Failed to create the indexer after 15 attempts"
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
        elseif($exists -and $update) {
            Write-Host -ForegroundColor Green "Updating Indexer '$($indexer["name"])' for Azure Search"
            Invoke-RestMethod -Method Put -Uri ( $this.azureSearchEndpoint + "/indexers('" + $indexer["name"] + "')?api-version=2024-09-01-preview" ) -Headers @{ "api-key" = $this.azureSearchKey } -Body ( $indexer | ConvertTo-Json -Depth 100 ) -ContentType "application/json" | Out-Null
        }
    }
}




$azSrcDeploy = [AzureSearchDeployment]::new($resourceGroupName, $azureSearchName)
$azSrcDeploy.SetRenderDebugJson($debugRenderedJson)



$datasource = Get-Content (Join-Path $scriptPath "documents-datasource.json") | ConvertFrom-Json -AsHashtable -Depth 100
$datasource["credentials"]["connectionString"] = ( 'ResourceId=' + $storageAccountId + ';' )
$azSrcDeploy.CreateDataSource($datasource, $updateAll)




$index = Get-Content (Join-Path $scriptPath "documents-index.json") | ConvertFrom-Json -AsHashtable -Depth 100
$index["vectorSearch"]["vectorizers"] | Where-Object { $_["kind"] -eq "azureOpenAI" } | ForEach-Object {
    $_["azureOpenAIParameters"]["resourceUri"] = $openAiBaseUrl
    $_["azureOpenAIParameters"]["deploymentId"] = $adaDeploymentName
}
$azSrcDeploy.CreateIndex($index, $updateAll)



$skillset = Get-Content (Join-Path $scriptPath "documents-skillset.json") | ConvertFrom-Json -AsHashtable -Depth 100
$skillset["skills"] | Where-Object { $_["@odata.type"] -eq "#Microsoft.Skills.Text.AzureOpenAIEmbeddingSkill" } | ForEach-Object {
    $_["resourceUri"] = $openAiBaseUrl
    $_["deploymentId"] = $adaDeploymentName
}
$azSrcDeploy.CreateSkillset($skillset, $updateAll)


$indexer = Get-Content (Join-Path $scriptPath "documents-indexer.json") | ConvertFrom-Json -AsHashtable -Depth 100
$azSrcDeploy.CreateIndexer($indexer, $updateAll)

