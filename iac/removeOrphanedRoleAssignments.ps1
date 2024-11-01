param(
    [Parameter(Mandatory = $true)]
    [string]$resourceGroupName
)



class GraphLite {
    hidden [string] $graphToken
    GraphLite() {
        $this.graphToken = ConvertFrom-SecureString -SecureString (Get-AzAccessToken -ResourceUrl "https://graph.microsoft.com" -AsSecureString -WarningAction Ignore).Token -AsPlainText -WarningAction Ignore
    }

    [bool] objectExists([string] $objectId) {
        # check if the object exists (ATTENTION: in case of insufficient permissions, the object will be assumed to not exist)
        try{
            $this.getObject($objectId)
            return $true
        }
        catch {
            return $false
        }
    }

    [PSCustomObject] getObject([string] $objectId) {
        # try different methods to get the object
        try{ return $this.getDirectoryObject($objectId) } catch { }
        try{ return $this.getServicePrincipal($objectId) } catch { }
        try{ return $this.getUser($objectId) } catch { }
        throw "Could not find the object with the id $objectId"
    }

    [PSCustomObject] getDirectoryObject([string] $objectId) {
        # requires (least priviledge): Directory.Read.All
        return Invoke-RestMethod -Method Get -Uri "https://graph.microsoft.com/v1.0/directoryObjects/$objectId" -Headers @{ "Authorization" = ( "Bearer " + $this.graphToken ) }
    }
    [PSCustomObject] getServicePrincipal([string] $objectId) {
        # requires (least priviledge): Application.Read.All
        return Invoke-RestMethod -Method Get -Uri "https://graph.microsoft.com/v1.0/servicePrincipals/$objectId" -Headers @{ "Authorization" = ( "Bearer " + $this.graphToken ) }
    }
    [PSCustomObject] getUser([string] $objectId) {
        # requires (least priviledge): User.Read.All
        return Invoke-RestMethod -Method Get -Uri "https://graph.microsoft.com/v1.0/users/$objectId" -Headers @{ "Authorization" = ( "Bearer " + $this.graphToken ) }
    }
}

class GraphLiteCache  {
    hidden [GraphLite] $graphLiteObject
    hidden [hashtable] $cache
    GraphLiteCache([GraphLite] $graphLiteObject) {
        $this.graphLiteObject = $graphLiteObject
        $this.cache = @{}
    }

    [bool] objectExists([string] $objectId) {
        try {
            $this.getObject($objectId)
            return $true
        }
        catch {
            return $false
        }
    }

    [PSCustomObject] getObject([string] $objectId) {
        if($this.cache.ContainsKey($objectId)) {
            if ($null -eq $this.cache[$objectId]) {
                throw "The object with the id $objectId does not exist"
            }
            return $this.cache[$objectId]
        }
        try {
            $this.cache[$objectId] = $this.graphLiteObject.getObject($objectId)
        }
        catch {
            $this.cache[$objectId] = $null
            throw $_
        }
        return $this.cache[$objectId]
    }

    [void] clearCache() {
        $this.cache = @{}
    }
}


$graphLiteObject = [GraphLiteCache]::new( [GraphLite]::new() )


function Remove-OrphanedRoleAssignments {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Scope
    )

    # get the assignments for the resource
    foreach($assignment in Get-AzRoleAssignment -Scope $Scope) {
        # in case the object type is unknown, the object id does no longer exist
        if($assignment.ObjectType -eq "Unknown") {
            # saveguard check if the object id is still valid (in case of insufficient permissions, the object will be assumed to not exist)
            if(-not $graphLiteObject.objectExists($assignment.ObjectId)) {
                Write-Host (" - Removing role assignment: " + $assignment.RoleDefinitionName + " for " + $assignment.ObjectId)
                $result = $assignment | Remove-AzRoleAssignment -ErrorAction Continue
                Write-Host (" - Result: " + $result)
            }
        }
    }
}

Write-Host ("Removing orphaned role assignments on objects in resource group $resourceGroupName")
$rg = Get-AzResourceGroup -Name $resourceGroupName -ErrorAction Stop
Write-Host -ForegroundColor Green ("Resource Group: " + $resourceGroupName)
Remove-OrphanedRoleAssignments -Scope $rg.ResourceId

# iterate through all the resources in the resource group
foreach($resource in (Get-AzResource -ResourceGroupName $resourceGroupName)) {
    Write-Host -ForegroundColor Green ("Resource: " + $resource.Name + "    (" + $resource.Type + ")")
    Remove-OrphanedRoleAssignments -Scope $resource.Id
}

