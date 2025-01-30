param(
    [Parameter(Mandatory = $true)]
    [string]$resourceGroupName,
    [Parameter(Mandatory = $true)]
    [string]$azureSearchName,

    [ValidateSet("key1", "key2", "aad")]
    [string]$authenticationMode = "key1",

    [ValidateLength(10, 600)]
    [string]$storageAccountId,
    [ValidateLength(10, 600)]
    [string]$openAiBaseUrl,
    [string]$adaDeploymentName = "text-embedding-ada-002",
    [switch]$debugRenderedJson,
    [switch]$updateAll,
    [switch]$disableRoleAssignment
)

Import-Module Az.Search

# get the path of this script
$scriptPath = Split-Path -parent $MyInvocation.MyCommand.Definition


class AzureSearchDeployment {
    hidden [string] $azureSearchEndpoint
    hidden [string] $azureSearchKey
    hidden [hashtable] $authHeaders = @{ }
    hidden [bool] $debugRenderedJson = $false

    AzureSearchDeployment([string]$resourceGroupName, [string]$azureSearchName, [string]$authenticationMode) {
        $this.azureSearchEndpoint = ( 'https://' + $azureSearchName + '.search.windows.net' )
        if($authenticationMode -eq "key1") {
            $this.authHeaders = @{
                "api-key" = (Get-AzSearchAdminKeyPair -ResourceGroupName $resourceGroupName -ServiceName $azureSearchName -ErrorAction Stop -WarningAction Ignore).Primary
            }
        }
        elseif($authenticationMode -eq "key2") {
            $this.authHeaders = @{
                "api-key" = (Get-AzSearchAdminKeyPair -ResourceGroupName $resourceGroupName -ServiceName $azureSearchName -ErrorAction Stop -WarningAction Ignore).Secondary
            }
        }
        elseif($authenticationMode -eq "aad") {
            $this.authHeaders = @{
                "Authorization" = ( "Bearer " + (Get-AzAccessToken -ResourceUrl "https://search.azure.com" -ErrorAction Stop -WarningAction Ignore).Token )
            }
        }
        else {
            throw "Invalid authentication mode '$authenticationMode' specified. Must be 'key1', 'key2', or 'aad'"
        }
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

    hidden [hashtable] GetMergedHeaders([hashtable] $headers) {
        foreach($header in $this.authHeaders.GetEnumerator()) {
            $headers[$header.Key] = $header.Value
        }
        return $headers
    }

    [void] CreateDataSource([hashtable] $datasource, [bool]$update = $false) {
        $this.RenderDebugJson($datasource, "Data Source")
        if(-not $datasource.ContainsKey("name")) {
            throw "Data Source must have a 'name' key"
        }
        try {
            Invoke-RestMethod -Method Get -Uri ( $this.azureSearchEndpoint + "/datasources('" + $datasource["name"] + "')?api-version=2024-09-01-preview" ) -Headers $this.GetMergedHeaders(@{}) -ErrorAction Stop | Out-Null
            Write-Host -ForegroundColor Yellow "Data Source '$($datasource["name"])' already exists for Azure Search"
            $exists = $true
        }
        catch {
            $exists = $false
        }
        if(-not $exists) {
            Write-Host -ForegroundColor Green "Creating Data Source '$($datasource["name"])' for Azure Search"
            Invoke-RestMethod -Method Post -Uri ( $this.azureSearchEndpoint + "/datasources?api-version=2024-09-01-preview" ) -Headers $this.GetMergedHeaders(@{}) -Body ( $datasource | ConvertTo-Json -Depth 100 ) -ContentType "application/json" | Out-Null
        }
        elseif($exists -and $update) {
            Write-Host -ForegroundColor Green "Updating Data Source '$($datasource["name"])' for Azure Search"
            Invoke-RestMethod -Method Put -Uri ( $this.azureSearchEndpoint + "/datasources('" + $datasource["name"] + "')?api-version=2024-09-01-preview" ) -Headers $this.GetMergedHeaders(@{}) -Body ( $datasource | ConvertTo-Json -Depth 100 ) -ContentType "application/json" | Out-Null
        }
    }

    [void]CreateIndex([hashtable] $index, [bool]$update = $false) {
        $this.RenderDebugJson($index, "Index")
        if(-not $index.ContainsKey("name")) {
            throw "Index must have a 'name' key"
        }
        try {
            Invoke-RestMethod -Method Get -Uri ( $this.azureSearchEndpoint + "/indexes('" + $index["name"] + "')?api-version=2024-09-01-preview" ) -Headers $this.GetMergedHeaders(@{}) -ErrorAction Stop | Out-Null
            Write-Host -ForegroundColor Yellow "Index '$($index["name"])' already exists for Azure Search"
            $exists = $true
        }
        catch {
            $exists = $false
        }
        if(-not $exists) {
            Write-Host -ForegroundColor Green "Creating Index '$($index["name"])' for Azure Search"
            Invoke-RestMethod -Method Post -Uri ( $this.azureSearchEndpoint + "/indexes?api-version=2024-09-01-preview" ) -Headers $this.GetMergedHeaders(@{}) -Body ( $index | ConvertTo-Json -Depth 100 ) -ContentType "application/json" | Out-Null
        }
        elseif($exists -and $update) {
            Write-Host -ForegroundColor Green "Updating Index '$($index["name"])' for Azure Search"
            Invoke-RestMethod -Method Put -Uri ( $this.azureSearchEndpoint + "/indexes('" + $index["name"] + "')?api-version=2024-09-01-preview" ) -Headers $this.GetMergedHeaders(@{}) -Body ( $index | ConvertTo-Json -Depth 100 ) -ContentType "application/json" | Out-Null
        }
    }

    [void]CreateSkillset([hashtable] $skillset, [bool]$update = $false) {
        $this.RenderDebugJson($skillset, "Skillset")
        if(-not $skillset.ContainsKey("name")) {
            throw "Skillset must have a 'name' key"
        }
        try {
            Invoke-RestMethod -Method Get -Uri ( $this.azureSearchEndpoint + "/skillsets('" + $skillset["name"] + "')?api-version=2024-09-01-preview" ) -Headers $this.GetMergedHeaders(@{}) -ErrorAction Stop | Out-Null
            Write-Host -ForegroundColor Yellow "Skillset '$($skillset["name"])' already exists for Azure Search"
            $exists = $true
        }
        catch {
            $exists = $false
        }
        if(-not $exists) {
            Write-Host -ForegroundColor Green "Creating Skillset '$($skillset["name"])' for Azure Search"
            Invoke-RestMethod -Method Post -Uri ( $this.azureSearchEndpoint + "/skillsets?api-version=2024-09-01-preview" ) -Headers $this.GetMergedHeaders(@{}) -Body ( $skillset | ConvertTo-Json -Depth 100 ) -ContentType "application/json" | Out-Null
        }
        elseif($exists -and $update) {
            Write-Host -ForegroundColor Green "Updating Skillset '$($skillset["name"])' for Azure Search"
            Invoke-RestMethod -Method Put -Uri ( $this.azureSearchEndpoint + "/skillsets('" + $skillset["name"] + "')?api-version=2024-09-01-preview" ) -Headers $this.GetMergedHeaders(@{}) -Body ( $skillset | ConvertTo-Json -Depth 100 ) -ContentType "application/json" | Out-Null
        }
    }

    [void]CreateIndexer([hashtable] $indexer, [bool]$update = $false) {
        $this.RenderDebugJson($indexer, "Indexer")
        if(-not $indexer.ContainsKey("name")) {
            throw "Indexer must have a 'name' key"
        }
        try {
            Invoke-RestMethod -Method Get -Uri ( $this.azureSearchEndpoint + "/indexers('" + $indexer["name"] + "')?api-version=2024-09-01-preview" ) -Headers $this.GetMergedHeaders(@{}) -ErrorAction Stop | Out-Null
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
                    Invoke-RestMethod -Method Post -Uri ( $this.azureSearchEndpoint + "/indexers?api-version=2024-09-01-preview" ) -Headers $this.GetMergedHeaders(@{}) -Body ( $indexer | ConvertTo-Json -Depth 100 ) -ContentType "application/json" | Out-Null
                    break
                }
                catch {
                    if($tries -gt 15) {
                        Write-Host -ForegroundColor Red " - Failed to create the indexer after 15 attempts"
                        throw $_
                    }    
                    elseif(
                        $_.Exception.Message -like "*Unable to retrieve blob container for account*" -or 
                        $_.Exception.Message -like "*Credentials provided in the connection string are invalid or have expired*" -or
                        $_.Exception.Message -like "*Error with data source*"
                    ) {
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
            Invoke-RestMethod -Method Put -Uri ( $this.azureSearchEndpoint + "/indexers('" + $indexer["name"] + "')?api-version=2024-09-01-preview" ) -Headers $this.GetMergedHeaders(@{}) -Body ( $indexer | ConvertTo-Json -Depth 100 ) -ContentType "application/json" | Out-Null
        }
    }
}


if($authenticationMode -eq "aad" -and (-not $disableRoleAssignment)) {
    $objectId = ((Get-AzContext).Account.ExtendedProperties['HomeAccountId'] -split '\.')[0]
    if(((Get-AzContext).Account.ExtendedProperties['HomeAccountId'] -split '\.')[1] -ne (Get-AzContext).Tenant.Id) {
        $objectId = (Get-AzADUser -UserPrincipalName (Get-AzContext).Account.Id).Id
    }
    foreach($role in @("Search Index Data Contributor", "Search Service Contributor")) {
        $roleAssignment = Get-AzRoleAssignment -RoleDefinitionName $role -ResourceGroupName $resourceGroupName -ResourceName $azureSearchName -ResourceType "Microsoft.Search/searchServices" -ObjectId $objectId -ErrorAction SilentlyContinue
        if(-not $roleAssignment) {
            Write-Host "Assigning role $role to current user ($objectId)"
            try {
                New-AzRoleAssignment -ObjectId $objectId  -RoleDefinitionName $role -ResourceGroupName $resourceGroupName -ResourceName $azureSearchName -ResourceType "Microsoft.Search/searchServices" -ErrorAction Stop | Out-Null
            }
            catch {
                Write-Host "Failed to assign role $role to current user ($objectId)"
            }
        }
    }
}




$azSrcDeploy = [AzureSearchDeployment]::new($resourceGroupName, $azureSearchName, $authenticationMode)
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
