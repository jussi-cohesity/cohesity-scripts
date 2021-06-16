#### Example script for M365 autoprotect objects - Jussi Jaurola <jussi@cohesity.com>

### process commandline arguments
[CmdletBinding()]
param (
    [Parameter(Mandatory = $True)][string]$cohesityCluster, 
    [Parameter(Mandatory = $True)][string]$cohesityCred,
    [Parameter(Mandatory = $True)][string]$excludeDomain, 
    [Parameter(Mandatory = $True)][string]$protectionSource, 
    [Parameter(Mandatory = $True)][string]$protectionGroup 
    )

Get-Module -ListAvailable -Name Cohesity* | Import-Module

Write-Host "Importing credentials from credential file $($cohesityCred)" -ForegroundColor Yellow
Write-Host "Connecting to Cohesity Cluster $($cohesityCluster)" -ForegroundColor Yellow

$Credential = Import-Clixml -Path ($cohesityCred)
try {
    Connect-CohesityCluster -Server $cohesityCluster -Credential $Credential
    Write-Host "Connected to Cohesity Cluster $($cohesityCluster)" -ForegroundColor Yellow
} catch {
    write-host "Cannot connect to Cohesity cluster $($cohesityCluster)" -ForegroundColor Yellow
    exit
}

Write-Host "Refreshing source $protectionSource. This could take long. Please wait!" -ForegroundColor Yellow
### Get source & Refresh source
$source = Get-CohesityProtectionSource -Environments kO365 | Where { $_.protectionSource.name -match $protectionSource }
$lastRefresh = $source.registrationInfo.refreshTimeUsecs
Update-CohesityProtectionSource -Id $($source.protectionSource.id)


### List all objects
Write-Host "Getting objects for source $protectionSource"
$availableObjects = Get-CohesityProtectionSourceObject -Environments kO365 | Where { $_.parentId -match $($source.protectionSource.id) } | Where { $_.office365ProtectionSource.type -eq 'kUser' } | Where { $_.office365ProtectionSource.primarySMTPAddress -notmatch $($excludeDomain) }

if (!$availableObjects) {
    Write-Host "Couldnt find any objects to protect. Please check!" -ForegroundColor Red
    exit
}
$objects = @{}

foreach ($object in $availableObjects) {
    $objectId = $object.id
    $objectName = $object.office365ProtectionSource.name
    $objectSmtp = $object.office365ProtectionSource.primarySMTPAddress

    if($objectName -notin $objects.Keys) {
        $objects[$objectName] = @{}
        $objects[$objectName]['objectId'] = $objectId
        $objects[$objectName]['primarySMTPAddress'] = $objectSmtp
    }
}

### Get protectiongroup

Write-Host "Getting information for ProtectionGroup $protectionGroup" -ForegroundColor Yellow
$job = Get-CohesityProtectionJob -Names $protectionGroup
$jobSourceIds = $job.sourceIds

if (!$jobSourceIds) {
    Write-Host "ProtectionGroup $protectionGroup not found!" -ForegroundColor Red
    exit
}


### Update sourceIds to match current status
Write-Host "Building new sourceId list for ProtectionGroup $protectionGroup" -ForegroundColor Yellow
$newSourceIds = [System.Collections.ArrayList]::new()
$objects.GetEnumerator() | ForEach-Object {
    $newSourceIds.Add($_.Value.objectId)
}

## Update protectiongroup with new sourceId's
Write-Host "Updating ProtectionGroup $protectionGroup" -ForegroundColor Yellow
$job.sourceIds = $newSourceIds
try { 
    Set-CohesityProtectionJob -ProtectionJob $job -Confirm:$false     
} catch {
    write-host "Cannot update protectiongroup $protectionGroup" -ForegroundColor Red
    exit
}                                                                                                                                
