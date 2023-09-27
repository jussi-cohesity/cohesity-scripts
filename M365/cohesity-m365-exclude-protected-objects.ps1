#### Example script to remove protected users from job - Jussi Jaurola <jussi@cohesity.com>

### process commandline arguments
[CmdletBinding()]
param (
    [Parameter(Mandatory = $True)][string]$cohesityCluster, 
    [Parameter(Mandatory = $True)][string]$apiKey,
    [Parameter(Mandatory = $True)][string]$protectionGroup, #Cohesity ProtectionGroup to pick protected objects
    [Parameter(Mandatory = $True)][string]$autoProtectGroup #Cohesity autoprotection group to add excludes
    )

Get-Module -ListAvailable -Name Cohesity* | Import-Module

Write-Host "Connecting to Cohesity Cluster $($cohesityCluster)" -ForegroundColor Yellow

$Credential = Import-Clixml -Path ($cohesityCred)
try {
    Connect-CohesityCluster -Server $cohesityCluster -APIkey $apiKey
    Write-Host "Connected to Cohesity Cluster $($cohesityCluster)" -ForegroundColor Yellow
} catch {
    write-host "Cannot connect to Cohesity cluster $($cohesityCluster)" -ForegroundColor Red
    exit
}

### List all protected objects from source ProtectionGroup
Write-Host "Getting protected objects from $protectionGroup" -ForegroundColor Yellow

$protectedSourceIds = (Get-CohesityProtectionJob -Names $protectionGroup).sourceIds

if (!$protectedSourceIds) {
    Write-Host "Source job $protectionGroup doesnt have any objects manually protected. Please check!" -ForegroundColor Red
    exit
}

### Get protectiongroup

Write-Host "Getting autoprotect ProtectionGroup $autoProtectGroup" -ForegroundColor Yellow
$job = Get-CohesityProtectionJob -Names $autoProtectGroup

if (!$job) {
    Write-Host "Autoprotect ProtectionGroup $autoProtectGroup not found!" -ForegroundColor Red
    exit
}

## Update protectiongroup with new sourceId's
Write-Host "Excluding $($protectedSourceIds.count) users from autoprotect ProtectionGroup $autoProtectGroup" -ForegroundColor Yellow
$job.excludeSourceIds = $protectedSourceIds
try { 
    Set-CohesityProtectionJob -ProtectionJob $job -Confirm:$false     
} catch {
    write-host "Cannot update protectiongroup $protectionGroup" -ForegroundColor Red
    exit
}     
