### Example script include/exclude users with ADgroups, users with smtp-domains, sites or teams for M365 protection group - Jussi Jaurola <jussi@cohesity.com>

### process commandline arguments
[CmdletBinding()]
param (
    [Parameter(Mandatory = $True)][string]$apiKey,
    [Parameter(Mandatory = $True)][string]$cohesityCluster,
    [Parameter(Mandatory = $True)][string]$protectionSource, 
    [Parameter(Mandatory = $True)][string]$protectionGroup,
    [Parameter(Mandatory = $False)][string]$waitTimeSecs = 60,
    [Parameter(Mandatory = $False)][array]$excludeAdGroups,
    [Parameter(Mandatory = $False)][array]$includeAdGroups,
    [Parameter(Mandatory = $False)][array]$excludeAds,
    [Parameter(Mandatory = $False)][array]$includeAds,
    [Parameter(Mandatory = $False)][array]$excludeSMTPdomains,
    [Parameter(Mandatory = $False)][array]$includeSMTPdomains,
    [Parameter(Mandatory = $False)][array]$includeSites,
    [Parameter(Mandatory = $False)][array]$excludeSites,
    [Parameter(Mandatory = $False)][array]$includeTeams,
    [Parameter(Mandatory = $False)][array]$excludeTeams

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
$allAvailableObjects = Get-CohesityProtectionSourceObject -Environments kO365 | Where { $_.parentId -match $($source.protectionSource.id) }
$availableUsers = @{}
$availableSites = @{}

foreach ($availableUser in ($allAvailableObjects | Where { $_.office365ProtectionSource.type -eq 'kUser' })) {
    $emailAddress = $availableUser.office365ProtectionSource.primarySMTPAddress
    $userId = $availableUser.id
    $availableUsers.Add($emailAddress, $userId)
}

foreach ($availableSite in ($allAvailableObjects | Where { $_.office365ProtectionSource.type -eq 'kSite' })) {
    $siteId = $availableSite.id
    $site = $availableSite.office365ProtectionSource.name
    $availableSites.Add($site, $siteId)
}


$includeDefined = $False
$excludeDefined = $False

$excludeIds = [System.Collections.ArrayList]::new()
$includeIds = [System.Collections.ArrayList]::new()

if ($excludeAds) {
    $excludeDefined = $True
    Write-Host "Exclude AD(s) defined" -ForegroundColor Yellow
    Write-Host "    Getting users from AD(s): $($excludeAds)" -ForegroundColor Yellow

    foreach ($excludeAd in $excludeAds) {
        $users = Get-ADUser -server $excludeAd -Properties EmailAddress | Select EmailAddress

        foreach ($user in $users)
        {
            $excludeIds.Add(($availableUsers[$user.EmailAddress])) | out-null
        }
    }
}

if ($includeAds) {
    $includeDefined = $True

    Write-Host "Include AD(s) defined" -ForegroundColor Yellow
    Write-Host "    Getting users from AD(s): $($includeAds)" -ForegroundColor Yellow

    foreach ($includeAd in $includeAds) {
        $users = Get-ADUser -server $includeAd -Properties EmailAddress | Select EmailAddress

        foreach ($user in $users)
        {
            $includeIds.Add(($availableUsers[$user.EmailAddress])) | out-null
        }
    }
    
}

if ($excludeAdGroups) {
    $exludeDefined = $True
    Write-Host "Exclude AG groups defined" -ForegroundColor Yellow
    Write-Host "    Getting users from AD group(s): $($excludeAdGroups)" -ForegroundColor Yellow

    foreach ($excludeAdGroup in $excludeAdGroups) {
        $adGroup = $excludeAdGroup -split "@"[0]
        $adDomain = $excludeAdGroup -split "@"[1]
        $users = Get-ADGroupMember -identity $adGroup -server $adDomain -Recursive | Get-ADUser -Properties EmailAddress | Select EmailAddress
    
        foreach ($user in $users) {
            $excludeIds.Add(($availableUsers[$user.EmailAddress])) | out-null
        }
    }
}

if ($excludeSMTPdomains) {
    $excludeDefined = $True
    Write-Host "Exclude SMTP domains defined" -ForegroundColor Yellow
    Write-Host "    Getting users for domain(s): $($excludeSMTPdomains)" -ForegroundColor Yellow
    
    foreach ($excludeSMTPdomain in $excludeSMTPdomains) {
        $users = $allAvailableObjects | Where { $_.office365ProtectionSource.type -eq 'kUser' } | Where { $_.office365ProtectionSource.primarySMTPAddress -match $($excludeSMTPdomain) }

        foreach ($user in $users) {
            $excludeIds.Add($user.id) | out-null
        }

    }
}

if ($includeAdGroups) {
    $includeDefined = $True
    
    Write-Host "Include AG groups defined" -ForegroundColor Yellow
    Write-Host "    Getting users from AD group(s): $($includeAdGroups)" -ForegroundColor Yellow

    foreach ($includeAdGroup in $includeAdGroups) {
        $adGroup = $includeAdGroup -split "@"[0]
        $adDomain = $includeAdGroup -split "@"[1]
        $users = Get-ADGroupMember -identity $adGroup -server $adDomain -Recursive | Get-ADUser -Properties EmailAddress | Select EmailAddress
    
        foreach ($user in $users) {
            $includeIds.Add(($availableUsers[$user.EmailAddress])) | out-null
        }
    }
}

if ($includeSMTPdomains) {
    $includeDefined = $True

    Write-Host "Include SMTP domains defined" -ForegroundColor Yellow
    Write-Host "    Getting users from domain(s): $($includeSMTPdomains)" -ForegroundColor Yellow

    foreach ($includeSMTPdomain in $includeSMTPdomains) {
        $users = $allAvailableObjects | Where { $_.office365ProtectionSource.type -eq 'kUser' } | Where { $_.office365ProtectionSource.primarySMTPAddress -match $($includeSMTPdomain) }

        foreach ($user in $users) {
            $includeIds.Add($user.id) | out-null
        }
    }
}

if ($includeSites) {
    $includeDefined = $True

    Write-Host "Including sites defined" -ForegroundColor Yellow
    Write-Host "    Getting IDs for site(s): $($includeSites)" -ForegroundColor

    foreach ($includeSite in $includeSites) {
        $site = $allAvailableObjects | Where { $_.office365ProtectionSource.type -eq 'kSite' } | Where { $_.office365ProtectionSource.name -match $($includeSite) }
        $includeIds.Add($site.id) | out-null
    }

}

if ($excludeSites) {
    $excludeDefined = $True

    Write-Host "Excluding sites defined" -ForegroundColor Yellow
    Write-Host "    Getting IDs for site(s): $($excludeSites)" -ForegroundColor Yellow

    foreach ($excludeSite in $excludeSites) {
        $site = $allAvailableObjects | Where { $_.office365ProtectionSource.type -eq 'kSite' } | Where { $_.office365ProtectionSource.name -match $($excludeSite) }
        $excludeIds.Add($site.id) | out-null
    }

}

if ($includeTeams) {
    $includeDefined = $True

    Write-Host "Including teams defined" -ForegroundColor Yellow
    Write-Host "    Getting IDs for teams(s): $($includeTeams)" -ForegroundColor

    foreach ($includeTeam in $includeTeams) {
        $teams = $allAvailableObjects | Where { $_.office365ProtectionSource.type -eq 'kTeam' } | Where { $_.office365ProtectionSource.name -match $($includeTeam) }
        $includeIds.Add($teams.id) | out-null
    }

}

if ($excludeTeams) {
    $excludeDefined = $True

    Write-Host "Excluding teams defined" -ForegroundColor Yellow
    Write-Host "    Getting IDs for teams(s): $($excludeTeams)" -ForegroundColor

    foreach ($includeTeam in $includeTeams) {
        $teams = $allAvailableObjects | Where { $_.office365ProtectionSource.type -eq 'kTeam' } | Where { $_.office365ProtectionSource.name -match $($excludeTeam) }
        $excludeIds.Add($teams.id) | out-null
    }
    
}

if (($includeDefined) -or ($excludeDefined)) {
    Write-Host "Getting information for ProtectionGroup $protectionGroup" -ForegroundColor Yellow
    $job = Get-CohesityProtectionJob -Names $protectionGroup
    Write-Host "Updating ProtectionGroup $protectionGroup" -ForegroundColor Yellow
    
    if ($includeIds) {
        Write-Host "    Including $($includeIds.count) objects" -ForegroundColor Yellow
        if ($job.sourceIds) {
            $job.sourceIds = $includeIds
        } else {
            $job | Add-Member -Membertype NoteProperty -Name "sourceIds" -Value $includeIds
        }
    }

    if ($excludeIds) {
        Write-Host "    Excluding $($excludeIds.count) objects" -ForegroundColor Yellow
        if ($job.excludeSourceIds) {
            $job.excludeSourceIds = $excludeIds
        } else {
            $job | Add-Member -Membertype NoteProperty -Name "excludeSourceIds" -Value $excludeIds
        }
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
