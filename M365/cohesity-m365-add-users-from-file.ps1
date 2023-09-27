### Example script to add users from input file to M365 protection group - Jussi Jaurola <jussi@cohesity.com>

### process commandline arguments
[CmdletBinding()]
param (
    [Parameter(Mandatory = $True)][string]$apiKey,
    [Parameter(Mandatory = $True)][string]$cohesityCluster,
    [Parameter(Mandatory = $True)][string]$protectionSource, 
    [Parameter(Mandatory = $True)][string]$protectionGroup,
    [Parameter(Mandatory = $True)][string]$usersFile
    )

Get-Module -ListAvailable -Name Cohesity* | Import-Module

Write-Host "Importing users from file $usersFile" -ForegroundColor Yellow
$users = Get-Content -path $usersFile
if (!$users) {
    Write-Host "Couldnt find any users from $usersFile. Please check!" -ForegroundColor Red
    exit
} else {
    Write-Host "Imported $($users.count) users from $usersFile" -ForegroundColor Yellow
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
$source = Get-CohesityProtectionSource -Name $protectionSource

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
$availableObjects = Get-CohesityProtectionSourceObject -Environments kO365 | Where { $_.parentId -match $($source.protectionSource.id) } | Where { $_.office365ProtectionSource.type -eq 'kUser' }

if (!$availableObjects) {
    Write-Host "Couldnt find any objects to protect. Please check!" -ForegroundColor Red
    exit
}
$newSourceIds = [System.Collections.ArrayList]::new()
foreach ($user in $users) {
    Write-Host "Finding M365 source object for user $user" -ForegroundColor Yellow
    $userObjectId = ($availableObjects | Where { $_.name -match $user}).id

    if (!$userObjectId) {
        Write-Host "    Couldn't map user $user to any M365 objects" -ForegroundColor Red
    } else {
        $newSourceIds.Add($userObjectId) | out-null
        Write-Host "    Mapped user $user to M365 object id $userObjectId" -ForegroundColor Yellow
    }
}

### Get protectiongroup

Write-Host "Getting information for ProtectionGroup $protectionGroup" -ForegroundColor Yellow
$job = Get-CohesityProtectionJob -Names $protectionGroup

if (!$jobSourceIds) {
    Write-Host "ProtectionGroup $protectionGroup not found!" -ForegroundColor Red
    exit
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
