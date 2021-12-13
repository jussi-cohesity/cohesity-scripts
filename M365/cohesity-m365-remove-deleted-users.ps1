#### Example script to remove deleted users from job - Jussi Jaurola <jussi@cohesity.com>

### process commandline arguments
[CmdletBinding()]
param (
    [Parameter(Mandatory = $True)][string]$cohesityCluster, 
    [Parameter(Mandatory = $True)][string]$cohesityCred, 
    [Parameter(Mandatory = $True)][string]$protectionSource, #M365 source
    [Parameter(Mandatory = $True)][string]$protectionGroup  #Cohesity ProtectionGroup name
    )

Get-Module -ListAvailable -Name Cohesity* | Import-Module

Write-Host "Importing credentials from credential file $($cohesityCred)" -ForegroundColor Yellow
Write-Host "Connecting to Cohesity Cluster $($cohesityCluster)" -ForegroundColor Yellow

$Credential = Import-Clixml -Path ($cohesityCred)
try {
    Connect-CohesityCluster -Server $cohesityCluster -Credential $Credential
    Write-Host "Connected to Cohesity Cluster $($cohesityCluster)" -ForegroundColor Yellow
} catch {
    write-host "Cannot connect to Cohesity cluster $($cohesityCluster)" -ForegroundColor Red
    exit
}

Write-Host "Refreshing source $protectionSource. This could take long. Please wait!" -ForegroundColor Yellow
### Get source & Refresh source
$source = Get-CohesityProtectionSource -Environments kO365 | Where { $_.protectionSource.name -match $protectionSource }
if (!$source) { 
    Write-Host "Couldn't find source with name $protectionSource, please check!" -ForegroundColor Red
}
$lastRefresh = $source.registrationInfo.refreshTimeUsecs
try {
    Update-CohesityProtectionSource -Id $($source.protectionSource.id)
} catch {
    Write-Host "Couldn't refresh the source $($source.protectionSource.name)!" -ForegroundColor Red
}

### List all objects from source
Write-Host "Getting objects for source $protectionSource" -ForegroundColor Yellow
$availableObjects = Get-CohesityProtectionSourceObject -Environments kO365 | Where { $_.parentId -match $($source.protectionSource.id) } | Where { $_.office365ProtectionSource.type -eq 'kUser' }

if (!$availableObjects) {
    Write-Host "Couldnt find any objects to protect. Please check!" -ForegroundColor Red
    exit
}
$sourceObjectIds = [System.Collections.ArrayList]::new()

foreach ($object in $availableObjects) {
    $sourceObjectIds.Add($object.id) | out-null
}

### Get protectiongroup

Write-Host "Getting information for ProtectionGroup $protectionGroup" -ForegroundColor Yellow
$job = Get-CohesityProtectionJob -Names $protectionGroup
$jobSourceIds = $job.sourceIds

if (!$jobSourceIds) {
    Write-Host "ProtectionGroup $protectionGroup not found!" -ForegroundColor Red
    exit
}

$newSourceObjects = [System.Collections.ArrayList]::new()

foreach ($jobSourceId in $jobSourceIds) {
    
    if ($sourceObjectIds -eq $jobSourceId) {
        Write-Host "User $jobSourceId found still from source. Let's keep it!" -ForegroundColor Yellow
        $newSourceObjects.Add($jobSourceId) | out-null
    } else {
        Write-Host "User $jobSourceId is deleted so let's remove it also" -ForegroundColor Red
    }
}

## Update protectiongroup with new sourceId's
Write-Host "Updating ProtectionGroup $protectionGroup" -ForegroundColor Yellow
$job.sourceIds = $newSourceObjects
try { 
    Set-CohesityProtectionJob -ProtectionJob $job -Confirm:$false     
} catch {
    write-host "Cannot update protectiongroup $protectionGroup" -ForegroundColor Red
    exit
}                     
