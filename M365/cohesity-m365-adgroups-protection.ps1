### Example script to add users from AD group(s) to M365 protection group - Jussi Jaurola <jussi@cohesity.com>

### Note! You need to have cohesity-api.ps1 on same directory!

### process commandline arguments
[CmdletBinding()]
param (
    [Parameter(Mandatory = $True)][string]$apiKey,
    [Parameter(Mandatory = $True)][string]$cohesityCluster,
    [Parameter(Mandatory = $True)][string]$protectionSource, 
    [Parameter(Mandatory = $True)][string]$protectionGroup,
    [Parameter(Mandatory = $True)][array]$adGroups
    )

Get-Module -ListAvailable -Name Cohesity* | Import-Module

Write-Host "Getting users from AD group(s): $($adGroups)" -ForegroundColor Yellow

$adUsers = [System.Collections.ArrayList]::new()
foreach ($adGroup in $adGroups) {
    $users = Get-ADGroupMember -identity $adGroup -Recursive | Get-ADUser -Properties EmailAddress | Select EmailAddress
    
    foreach ($user in $users) {
        $adUsers.Add($user.EmailAddress) | out-null
    }
}

Write-Host "Connecting to Cohesity Cluster $($cohesityCluster)" -ForegroundColor Yellow

try {
    Connect-CohesityCluster -Server $cohesityCluster -APIkey $apiKey
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

### List all objects
Write-Host "Getting objects for source $protectionSource" -ForegroundColor Yellow
$availableObjects = Get-CohesityProtectionSourceObject -Environments kO365 | Where { $_.parentId -match $($source.protectionSource.id) } | Where { $_.office365ProtectionSource.type -eq 'kUser' } }

if (!$availableObjects) {
    Write-Host "Couldnt find any objects to protect. Please check!" -ForegroundColor Red
    exit
}
$objects = @{}

foreach ($object in $availableObjects) {
    $objectId = $object.id
    $objectName = $object.office365ProtectionSource.primarySMTPAddress

    if($objectName -notin $objects.Keys) {
        $objects[$objectName] = @{}
        $objects[$objectName]['objectId'] = $objectId
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

foreach ($aduser in $adusers) {
    $newSourceIds.Add($($objects[$aduser].objectId))
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
