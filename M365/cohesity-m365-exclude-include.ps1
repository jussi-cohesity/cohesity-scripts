### Example script include/exclude users with ADgroups and/or smtp domains for M365 protection group - Jussi Jaurola <jussi@cohesity.com>

### process commandline arguments
[CmdletBinding()]
param (
    [Parameter(Mandatory = $True)][string]$apiKey,
    [Parameter(Mandatory = $True)][string]$cohesityCluster,
    [Parameter(Mandatory = $True)][string]$protectionSource, 
    [Parameter(Mandatory = $True)][string]$protectionGroup,
    [Parameter(Mandatory = $True)][string]$waitTimeSecs = 60,
    [Parameter(Mandatory = $False)][array]$excludeAdGroups,
    [Parameter(Mandatory = $False)][array]$includeAdGroups,
    [Parameter(Mandatory = $False)][array]$excludeSMTPdomains,
    [Parameter(Mandatory = $False)][array]$includeSMTPdomains
    )

Get-Module -ListAvailable -Name Cohesity* | Import-Module

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
Write-Host "Source $protectionSource refreshed. Sleeping for $waitTimeSecs seconds" -ForegroundColor Yellow
Start-Sleep -s $waitTimeSecs

Write-Host "Getting all available objects for source $($protectionSource)" -ForegroundColor Yellow
$allAvailableObjects = Get-CohesityProtectionSourceObject -Environments kO365 | Where { $_.parentId -match $($source.protectionSource.id) } | Where { $_.office365ProtectionSource.type -eq 'kUser' }


$includeDefined = $False
$excludeDefined = $False

$excludeUsers = [System.Collections.ArrayList]::new()
$includeUsers = [System.Collections.ArrayList]::new()

if ($excludeAdGroups) {
    $exludeDefined = $True
    Write-Host "Exclude AG groups defined" -ForegroundColor Yellow
    Write-Host "    Getting users from AD group(s): $($excludeAdGroups)" -ForegroundColor Yellow

    foreach ($exlucedeAdGroup in $excludeAdGroups) {
        $users = Get-ADGroupMember -identity $excludeAdGroup -Recursive | Get-ADUser -Properties EmailAddress | Select EmailAddress
    
        foreach ($user in $users) {
            $userId = ($allAvailableObjects | Where { $_.parentId -match $($source.protectionSource.id) } | Where { $_.office365ProtectionSource.type -eq 'kUser' } | Where { $_.office365ProtectionSource.primarySMTPAddress -match $($user.EmailAddress) }).id
            $excludeUsers.Add($userId) | out-null
        }
    }
}

if ($excludeSMTPdomains) {
    $excludeDefined = $True
    Write-Host "Exclude SMTP domains defined" -ForegroundColor Yellow
    Write-Host "    Getting users for domain(s): $($excludeSMTPdomains)" -ForegroundColor Yellow
    
    foreach ($excludeSMTPdomain in $excludeSMTPdomains) {
        $users = Get-CohesityProtectionSourceObject -Environments kO365 | Where { $_.parentId -match $($source.protectionSource.id) } | Where { $_.office365ProtectionSource.type -eq 'kUser' } | Where { $_.office365ProtectionSource.primarySMTPAddress -match $($excludeSMTPdomain) }

        foreach ($user in $users) {
            $excludeUsers.Add($user.id) | out-null
        }

    }
}

if ($includeAdGroups) {
    $includeDefined = $True
    
    Write-Host "Include AG groups defined" -ForegroundColor Yellow
    Write-Host "    Getting users from AD group(s): $($includeAdGroups)" -ForegroundColor Yellow

    foreach ($includeAdGroup in $includeAdGroups) {
        $users = Get-ADGroupMember -identity $excludeAdGroup -Recursive | Get-ADUser -Properties EmailAddress | Select EmailAddress
    
        foreach ($user in $users) {
            $userId = ($allAvailableObjects | Where { $_.parentId -match $($source.protectionSource.id) } | Where { $_.office365ProtectionSource.type -eq 'kUser' } | Where { $_.office365ProtectionSource.primarySMTPAddress -match $($user.EmailAddress) }).id
            $includeUsers.Add($userId) | out-null
        }
    }
}

if ($includeSMTPdomains) {
    $includeDefined = $True

    Write-Host "Include SMTP domains defined" -ForegroundColor Yellow
    Write-Host "    Getting users from domain(s): $($includeSMTPdomains)" -ForegroundColor Yellow

    foreach ($includeSMTPdomain in $includeSMTPdomains) {
        $users = Get-CohesityProtectionSourceObject -Environments kO365 | Where { $_.parentId -match $($source.protectionSource.id) } | Where { $_.office365ProtectionSource.type -eq 'kUser' } | Where { $_.office365ProtectionSource.primarySMTPAddress -match $($includeSMTPdomain) }

        foreach ($user in $users) {
            $includeUsers.Add($user.id) | out-null
        }
    }
}

if (($includeDefined) -or ($excludeDefined)) {
    Write-Host "Getting information for ProtectionGroup $protectionGroup" -ForegroundColor Yellow
    $job = Get-CohesityProtectionJob -Names $protectionGroup
    Write-Host "Updating ProtectionGroup $protectionGroup" -ForegroundColor Yellow
    if ($includeUsers) {
        Write-Host "    Including $($includeUsers.count) users" -ForegroundColor Yellow
        $job.sourceIds = $includeUsers
    }

    if ($excludeUsers) {
        Write-Host "    Excluding $($excludeUsers.count) users" -ForegroundColor Yellow
        $job.excludeSourceIds = $excludeUsers
    }

    try { 
        Set-CohesityProtectionJob -ProtectionJob $job -Confirm:$false     
    } catch {
        write-host "Cannot update protectiongroup $protectionGroup" -ForegroundColor Red
        exit
    }         
} else {
    Write-Host "No include or exclude defined. Please check!" -ForegroundColor Red
    exit
}
