### Example script include/exclude users with ADgroups, users with smtp-domains, sites or teams for M365 protection group - Jussi Jaurola <jussi@cohesity.com>

###
### refreshAndWait = Enable source refresh and wait refresh (seconds)
### excludeAdGroups/includeAdGroups = Select which AD groups to be used as source (group@domain or just group)
### excludeAds/includeAds = Select all users from ADs
### excludeSMTPdomains/includeSMTPdomains = Filter only users matching SMTP domain (@domain)
### includeAllUsers = Add all users found with exchange enabled
### oneDriveOnly = Only look users with oneDrive enabled

### process commandline arguments
[CmdletBinding()]
param (
    [Parameter(Mandatory = $True)][string]$apiKey,
    [Parameter(Mandatory = $True)][string]$cohesityCluster,
    [Parameter(Mandatory = $True)][string]$protectionSource, 
    [Parameter(Mandatory = $True)][string]$protectionGroup,
    [Parameter(Mandatory = $False)][string]$refreshAndWait,
    [Parameter(Mandatory = $False)][array]$excludeAdGroups,
    [Parameter(Mandatory = $False)][array]$includeAdGroups,
    [Parameter(Mandatory = $False)][array]$excludeAds,
    [Parameter(Mandatory = $False)][array]$includeAds,
    [Parameter(Mandatory = $False)][array]$excludeSMTPdomains,
    [Parameter(Mandatory = $False)][array]$includeSMTPdomains,
    [Parameter(Mandatory = $False)][switch]$includeAllUsers,
    [Parameter(Mandatory = $False)][array]$includeSites,
    [Parameter(Mandatory = $False)][switch]$includeAllSites,
    [Parameter(Mandatory = $False)][array]$excludeSites,
    [Parameter(Mandatory = $False)][array]$includeTeams,
    [Parameter(Mandatory = $False)][switch]$includeAllTeams,
    [Parameter(Mandatory = $False)][array]$excludeTeams,
    [Parameter(Mandatory = $False)][switch]$oneDriveOnly,
    [Parameter(Mandatory = $False)][switch]$debugOnly,
    [Parameter(Mandatory = $False)][switch]$loggingEnabled

    )
    
$logFileName = "run-" + $(Get-Date -Format "dd_mm_yyyy_HH_mm") + "_log.txt"

Function logMessage()
{
 param
    (
    [Parameter(Mandatory=$true)] [string] $Message
    )
 
    Try {
        $TimeStamp = (Get-Date).toString("dd.MM.yyyy HH:mm:ss")
        $Line = "$TimeStamp - $Message"
        $Line | Out-File -Filepath $logFileName -Append
    }
    Catch {
        Write-host -f Red "Error:" $_.Exception.Message
    }
}
 
Get-Module -ListAvailable -Name Cohesity* | Import-Module

if ($loggingEnabled) { logMessage "Starting run" }
Write-Host "Connecting to Cohesity Cluster $($cohesityCluster)" -ForegroundColor Yellow

try {
    Connect-CohesityCluster -Server $cohesityCluster -APIkey $apiKey
    Write-Host "Connected to Cohesity Cluster $($cohesityCluster)" -ForegroundColor Yellow
    if ($loggingEnabled) { logMessage "Connected to Cohesity Cluster $($cohesityCluster)" }
} catch {
    write-host "Cannot connect to Cohesity cluster $($cohesityCluster)" -ForegroundColor Red
    exit
}

$source = Get-CohesityProtectionSource -Environments kO365 | Where { $_.protectionSource.name -match $protectionSource }
if (!$source) { 
    Write-Host "Couldn't find source with name $protectionSource, please check!" -ForegroundColor Red
}
if ($refreshandwait) {

    Write-Host "Refreshing source $protectionSource. This could take long. Please wait!" -ForegroundColor Yellow
    try {
        if ($loggingEnabled) { logMessage "Starting to refresh source" }
        Update-CohesityProtectionSource -Id $($source.protectionSource.id)
    } catch {
        Write-Host "Couldn't refresh the source $($source.protectionSource.name)!" -ForegroundColor Red
    }
    Write-Host "Source $protectionSource refreshed. Sleeping for $refreshAndWait seconds" -ForegroundColor Yellow
    if ($loggingEnabled) { logMessage "Source refreshed" }
    Start-Sleep -s $refreshandwait
}

if ($loggingEnabled) { logMessage "Collecting all available objects for source $($protectionSource)" }
Write-Host "Getting all available objects for source $($protectionSource)" -ForegroundColor Yellow
$allAvailableObjects = Get-CohesityProtectionSourceObject -Environments kO365 | Where { $_.parentId -match $($source.protectionSource.id) }
$availableUsers = @{}
$availableOnedriveUsers = @{}

if ($loggingEnabled) { logMessage "Collecting allAvailableObjects" }
foreach ($availableUser in ($allAvailableObjects | Where { $_.office365ProtectionSource.type -eq 'kUser' })) {
    $emailAddress = $availableUser.office365ProtectionSource.primarySMTPAddress
    if ($emailAddress) {
        if (!$availableUsers[$emailAddress]) {
            $userId = $availableUser.id

            if ($availableUser.office365ProtectionSource.userInfo.isMailboxEnabled -eq $True) {
                $availableUsers.Add($emailAddress, $userId)
                if ($loggingEnabled) { logMessage "    User $emailAddress has Exchange enabled. Adding." }
            }
            
            if ($availableUser.office365ProtectionSource.userInfo.isOneDriveEnabled -eq $True) {
                $availableOnedriveUsers.Add($emailAddress, $userId) 
                if ($loggingEnabled) { logMessage "    User $emailAddress has OneDrive enabled. Adding." }
            }
        }
    }
}



$includeDefined = $False
$excludeDefined = $False

$excludeIds = @()
$includeIds = @()
$includedUsers = @{}
$excludedUsers = @{}

if ($oneDriveOnly) { 
    Write-Host "OneDrive defined" -ForegroundColor Yellow 
    if ($loggingEnabled) { logMessage "OneDrive defined" }
}

if ($includeAllUsers) {
    $includeDefined = $True
    if ($loggingEnabled) { logMessage "All users selected. Adding!" }

    if ($oneDriveOnly) {
        foreach ($availableOnedriveUser in $availableOnedriveUsers.keys) {
            if (!$includedUsers[$availableOnedriveUser]) {
                $includedUsers.Add($availableOnedriveUser, $availableOnedriveUsers[$availableOnedriveUser])
                if ($loggingEnabled) { logMessage "    Added OneDriveUser $($availableOnedriveUsers[$availableOnedriveUser]) to includedUsers" }
            }
        }
    } else {
        foreach ($availableUser in $availableUsers.keys) {
            if (!$includedUsers[$availableUser]) {
                $includedUsers.Add($availableUser, $availableUsers[$availableUser])
                if ($loggingEnabled) { logMessage "    Added ExchangeUser $($availableUsers[$availableUser]) to includedUsers" }
            }
        }
    }
}

if ($excludeAds) {
    $excludeDefined = $True
    if ($loggingEnabled) { logMessage "Exclude AD(s) defined, getting users from AD(s)" }
    Write-Host "Exclude AD(s) defined" -ForegroundColor Yellow
    Write-Host "    Getting users from AD(s): $($excludeAds)" -ForegroundColor Yellow

    foreach ($excludeAd in $excludeAds) {
        $users = Get-ADUser -server $excludeAd -Filter * -Properties EmailAddress | Select EmailAddress

        if ($debugOnly) {
            $outFileName = "excludeAds_" + "$excludeAd" + "_Users.json"
            $users | ConvertTo-Json -depth 15 | Out-File $outFileName
        }
        
        foreach ($user in $users)
        {
            if ($user.EmailAddress) {
                if ($oneDriveOnly) {
                    if ($availableOnedriveUsers[$user.EmailAddress.ToString()]) {
                        if (!$excludedUsers[$user.EmailAddress]) {
                            $excludedUsers.Add($user.EmailAddress, $availableOnedriveUsers[$user.EmailAddress])
                            if ($loggingEnabled) { logMessage "    Added OneDriveUser $($user.EmailAddress) to excludedUsers" }
                        }
                    }
                } else {
                    if ($availableUsers[$user.EmailAddress.ToString()]) {
                        if (!$excludedUsers[$user.EmailAddress]) {
                            $excludedUsers.Add($user.EmailAddress, $availableUsers[$user.EmailAddress])
                            if ($loggingEnabled) { logMessage "    Added $($user.EmailAddress) to excludedUsers" }
                        }
                    }
                }
            }
        }
    }
}

if ($includeAds) {
    $includeDefined = $True
    if ($loggingEnabled) { logMessage "Include AD(s) defined, getting users from AD(s)" }
    Write-Host "Include AD(s) defined" -ForegroundColor Yellow
    Write-Host "    Getting users from AD(s): $($includeAds)" -ForegroundColor Yellow

    foreach ($includeAd in $includeAds) {
        $users = Get-ADUser -server $includeAd -Filter * -Properties EmailAddress | Select EmailAddress

        if ($debugOnly) {
            $outFileName = "includeAds_" + "$includeAd" + "_Users.json"
            $users | ConvertTo-Json -depth 15 | Out-File $outFileName
        }

        foreach ($user in $users)
        {
            if ($user.EmailAddress) {
                if ($oneDriveOnly) {
                    if ($availableOnedriveUsers[$user.EmailAddress.ToString()]) {
                        if(!$includedUsers[$user.EmailAddress]) {
                            $includedUsers.Add($user.EmailAddress, $availableOnedriveUsers[$user.EmailAddress])
                            if ($loggingEnabled) { logMessage "    Added OneDriveUser $($user.EmailAddress) to includedUsers" }
                        }         
                    }
                } else {
                    if ($availableUsers[$user.EmailAddress.ToString()]) {
                        if(!$includedUsers[$user.EmailAddress]) {
                            $includedUsers.Add($user.EmailAddress, $availableUsers[$user.EmailAddress])
                            if ($loggingEnabled) { logMessage "    Added $($user.EmailAddress) to includedUsers" }
                        }
                    }
                }
            }
        }
    }
    
}

if ($excludeAdGroups) {
    $exludeDefined = $True
    if ($loggingEnabled) { logMessage "Exclude AD groups defined, collecting users from AD group(s)" }
    Write-Host "Exclude AD groups defined" -ForegroundColor Yellow
    Write-Host "    Getting users from AD group(s): $($excludeAdGroups)" -ForegroundColor Yellow

    foreach ($excludeAdGroup in $excludeAdGroups) {
        if ($excludeAdGroup -match "@") {
            $adGroup = $($excludeAdGroup -split "@")[0]
            $adDomain = $($excludeAdGroup -split "@")[1]
            $users = Get-ADGroupMember -identity $adGroup -server $adDomain -Recursive | Get-ADUser -Properties EmailAddress | Select EmailAddress
        } else {
            $users = Get-ADGroupMember -identity $excludeAdGroup -Recursive | Get-ADUser -Properties EmailAddress | Select EmailAddress
        }

        if ($debugOnly) {
            $outFileName = "excludeAdGroups_" + "$excludeAdGroup" + "_Users.json"
            $users | ConvertTo-Json -depth 15 | Out-File $outFileName
        }
        
        foreach ($user in $users) {
            if ($user.EmailAddress) {
                if ($oneDriveOnly) {
                    if ($availableOnedriveUsers[$user.EmailAddress.ToString()]) {
                        if (!$excludedUsers[$user.EmailAddress]) {
                            $excludedUsers.Add($user.EmailAddress, $availableOnedriveUsers[$user.EmailAddress])
                            if ($loggingEnabled) { logMessage "    Added OneDriveUser $($user.EmailAddress) to excludedUsers" }
                        }   
                    }
                } else {
                    if ($availableUsers[$user.EmailAddress.ToString()]) {
                        if (!$excludedUsers[$user.EmailAddress]) {
                            $excludedUsers.Add($user.EmailAddress, $availableUsers[$user.EmailAddress])
                            if ($loggingEnabled) { logMessage "    Added $($user.EmailAddress) to excludedUsers" }
                        }
                    }
                }
            }
        }
    }
}

if ($includeAdGroups) {
    $includeDefined = $True
    if ($loggingEnabled) { logMessage "Include AD groups defined, collecting users from AD group(s)" }
    Write-Host "Include AD groups defined" -ForegroundColor Yellow
    Write-Host "    Getting users from AD group(s): $($includeAdGroups)" -ForegroundColor Yellow

    foreach ($includeAdGroup in $includeAdGroups) {
        if ($includeAdGroup -match "@") {
            $adGroup = $($includeAdGroup -split "@")[0]
            $adDomain = $($includeAdGroup -split "@")[1]
            $users = Get-ADGroupMember -identity $adGroup -server $adDomain -Recursive | Get-ADUser -Properties EmailAddress | Select EmailAddress
        } else {
            $users = Get-ADGroupMember -identity $includeAdGroup -Recursive | Get-ADUser -Properties EmailAddress | Select EmailAddress
        }

        if ($debugOnly) {
            $outFileName = "includeAdGroups" + "$includeAdGroup" + "_Users.json"
            $users | ConvertTo-Json -depth 15 | Out-File $outFileName
        }
        
        foreach ($user in $users) {
            if ($user.EmailAddress) {
                if ($oneDriveOnly) {
                    if ($availableOnedriveUsers[$user.EmailAddress.ToString()]) {
                        if(!$includedUsers[$user.EmailAddress]) {
                            $includedUsers.Add($user.EmailAddress, $availableOnedriveUsers[$user.EmailAddress])
                            if ($loggingEnabled) { logMessage "    Added OneDriveUser $($user.EmailAddress) to includedUsers" }
                        }     
                    }
                } else {
                    if ($availableUsers[$user.EmailAddress.ToString()]) {
                        if(!$includedUsers[$user.EmailAddress]) {
                            $includedUsers.Add($user.EmailAddress, $availableUsers[$user.EmailAddress])
                            if ($loggingEnabled) { logMessage "    Added $($user.EmailAddress) to includedUsers" }
                        }
                    }
                }
            }
        }
    }
}

if ($excludeSMTPdomains) {
    $excludeDefined = $True
    if ($loggingEnabled) { logMessage "Exclude SMTP domains defined" }
    Write-Host "Exclude SMTP domains defined" -ForegroundColor Yellow
    Write-Host "    Getting users for domain(s): $($excludeSMTPdomains)" -ForegroundColor Yellow
    
    foreach ($excludeSMTPdomain in $excludeSMTPdomains) {
        foreach ($excludeUser in ($includedUsers.keys | Where { $_ -match $excludeSMTPdomain})) {
            $includedUsers.Remove($excludeUser)
            if ($loggingEnabled) { logMessage "    Removed $($excludeUser) from includedUsers" }
        }
    }
}

if ($includeSMTPdomains) {
    $includeDefined = $True

    $newIncludedUsers = @{}

    if ($loggingEnabled) { logMessage "Include SMTP domains defined, collecting users from domain(s)" }
    Write-Host "Include SMTP domains defined" -ForegroundColor Yellow
    Write-Host "    Getting users from domain(s): $($includeSMTPdomains)" -ForegroundColor Yellow

    foreach ($includeSMTPdomain in $includeSMTPdomains) {
        foreach ($includeUser in ($includedUsers.keys | Where { $_ -match $includeSMTPdomain})) {
            if(!$newIncludedUsers[$includeUser]) {
                $newIncludedUsers.Add($includeUser, $includedUsers[$includeUser])
                if ($loggingEnabled) { logMessage "    Added $($includeUser) to includedUsers" }
            }
        }
    }
    $includedUsers = $newIncludedUsers
}

if ($includeSites) {
    $includeDefined = $True

    if ($loggingEnabled) { logMessage "Include sites defined" }
    Write-Host "Including sites defined" -ForegroundColor Yellow
    Write-Host "    Getting IDs for site(s): $($includeSites)" -ForegroundColor Yellow

    foreach ($includeSite in $includeSites) {
        $sites = $allAvailableObjects | Where { $_.office365ProtectionSource.type -eq 'kSite' } | Where { $_.office365ProtectionSource.name -match $($includeSite) }
        foreach ($site in $sites) {
            $includeIds += ($site.id) 
            if ($loggingEnabled) { logMessage "    Added $($site.id) to includeIds" }
        }
    }

}

if ($includeAllSites) {
    $includeDefined = $True

    if ($loggingEnabled) { logMessage "Include all sites defined" }
    Write-Host "Including all sites defined" -ForegroundColor Yellow
    Write-Host "    Getting IDs for all sites" -ForegroundColor Yellow

    $sites = $allAvailableObjects | Where { $_.office365ProtectionSource.type -eq 'kSite' }

    foreach ($site in $sites) {
        $includeIds += ($site.id)
        if ($loggingEnabled) { logMessage "    Added $($site.id) to includeIds" }
    }
}

if ($excludeSites) {
    $excludeDefined = $True

    if ($loggingEnabled) { logMessage "Exclude sites defined" }
    Write-Host "Excluding sites defined" -ForegroundColor Yellow
    Write-Host "    Getting IDs for site(s): $($excludeSites)" -ForegroundColor Yellow

    foreach ($excludeSite in $excludeSites) {
        $sites = $allAvailableObjects | Where { $_.office365ProtectionSource.type -eq 'kSite' } | Where { $_.office365ProtectionSource.name -match $($excludeSite) }
        foreach ($site in $sites) {
            $excludeIds += ($site.id)
            if ($loggingEnabled) { logMessage "    Added $($site.id) to excludeIds" }
        }
    }

}

if ($includeTeams) {
    $includeDefined = $True

    if ($loggingEnabled) { logMessage "Include teams defined" }
    Write-Host "Including teams defined" -ForegroundColor Yellow
    Write-Host "    Getting IDs for teams(s): $($includeTeams)" -ForegroundColor Yellow

    foreach ($includeTeam in $includeTeams) {
        $teams = $allAvailableObjects | Where { $_.office365ProtectionSource.type -eq 'kTeam' } | Where { $_.office365ProtectionSource.name -match $($includeTeam) }
        foreach ($team in $teams) {
            $includeIds += ($team.id)
            if ($loggingEnabled) { logMessage "    Added $($team.id) to includeIds" }
        }
    }
}

if ($includeAllTeams) {
    $includeDefined = $True

    if ($loggingEnabled) { logMessage "Include all teams defined" }
    Write-Host "Including all teams defined" -ForegroundColor Yellow
    Write-Host "    Getting IDs for all teams(s)" -ForegroundColor Yellow

    $teams = $allAvailableObjects | Where { $_.office365ProtectionSource.type -eq 'kTeam' }

    foreach ($team in $teams) {
        $includeIds += ($team.id)
        if ($loggingEnabled) { logMessage "    Added $($team.id) to includeIds" }
    }
}

if ($excludeTeams) {
    $excludeDefined = $True

    if ($loggingEnabled) { logMessage "Exclude teams defined" }
    Write-Host "Excluding teams defined" -ForegroundColor Yellow
    Write-Host "    Getting IDs for teams(s): $($excludeTeams)" -ForegroundColor Yellow

    foreach ($excludeTeam in $excludeTeams) {
        $teams = $allAvailableObjects | Where { $_.office365ProtectionSource.type -eq 'kTeam' } | Where { $_.office365ProtectionSource.name -match $($excludeTeam) }
        foreach ($team in $teams) {
            $excludeIds += ($team.id)
            if ($loggingEnabled) { logMessage "    Added $($team.id) to excludeIds" }
        }
    }
    
}

if (($includeDefined) -or ($excludeDefined)) {
    if ($loggingEnabled) { logMessage "Getting information for ProtectionGroup $protectionGroup" }
    Write-Host "Getting information for ProtectionGroup $protectionGroup" -ForegroundColor Yellow
    $job = Get-CohesityProtectionJob | Where { $_.name -eq $protectionGroup }
    if (!$job) {
        Write-Host "Failed to get ProtectionGroup $protectionGroup. Please check!" -ForegroundColor Red
        if ($loggingEnabled) { logMessage "Failed to get ProtectionGroup $protectionGroup" }
        exit
    }
    
    if ($loggingEnabled) { logMessage "ProtectionGroup details collected" }
    Write-Host "Updating ProtectionGroup $protectionGroup" -ForegroundColor Yellow

    if ($includedUsers) {
        foreach ($includedUser in $includedUsers.keys) {
            $includeIds += $includedUsers[$includedUser]
        }
    }

    if ($excludedUsers) {
        foreach ($excludedUser in $excludedUsers.keys) {
            $excludeIds += $excludedUsers[$excludedUser]
        }
    }
    
    if ($includeIds) {
        if ($excludeIds) { 
            $excludeIds = ($excludeIds | Sort | Get-Unique) 
            $includeIds = ($includeIds | Sort | Get-Unique | Where-Object { $excludeIds -notcontains $_ })
        } else {
            $includeIds = ($includeIds | Sort | Get-Unique)
        }
        
        if ($loggingEnabled) { logMessage "Including $($includeIds.count) objects" }
        Write-Host "    Including $($includeIds.count) objects" -ForegroundColor Yellow
        if ($job.sourceIds) {
            $job.sourceIds = $includeIds
            if ($loggingEnabled) { logMessage "Job includeIds updated" }
        } else {
            $job | Add-Member -Membertype NoteProperty -Name "sourceIds" -Value ($includeIds)
            if ($loggingEnabled) { logMessage "Job includeId added" }
        }
    }

    if ($excludeIds) {
        if (!$includeIds) {
            $excludeIds = ($excludeIds | Sort | Get-Unique)
        }
        if ($loggingEnabled) { logMessage "Excluding $($excludeIds.count) objects" }
        Write-Host "    Excluding $($excludeIds.count) objects" -ForegroundColor Yellow
        if ($job.excludeSourceIds) {
            $job.excludeSourceIds = $excludeIds
            if ($loggingEnabled) { logMessage "Job excludeIds updated" }
        } else {
            $job | Add-Member -Membertype NoteProperty -Name "excludeSourceIds" -Value ($excludeIds)
            if ($loggingEnabled) { logMessage "Job excludeIds added" }
        }
    }

    if (!$debugOnly) {
        if ($loggingEnabled) { logMessage "Updating job to cluster" }
        Set-CohesityProtectionJob -ProtectionJob $job -Confirm:$false 
        if ($loggingEnabled) { logMessage "Job updated" }
    } else {
        if ($loggingEnabled) { logMessage "Debug enabled, no actual job run but exporting JSONs" }
        Write-host "Debug enabled. Dumping variables to json only!" -ForegroundColor Yellow
    
        $job | ConvertTo-Json -depth 15 | Out-file job.json
        $includeIds | ConvertTo-Json -depth 15 | Out-file includeIds.json
        $excludeIds | ConvertTo-Json -depth 15 | Out-File excludeIds.json
        $source | Convertto-Json -depth 15 | Out-File source.json
        $allAvailableObjects | ConvertTo-Json -depth 15 | Out-File allAvailableObjects.json
        $availableUsers | ConvertTo-Json -depth 15 | Out-File availableUsers.json
        $availableOnedriveUsers | ConvertTo-Json -depth 15 | Out-File availableOnedriveUsers.json
        $includedUsers | ConvertTo-Json -depth 15 | Out-File includedUsers.json
        $excludedUsers | ConvertTo-Json -depth 15 | Out-File excludedUsers.json
        if ($loggingEnabled) { logMessage "JSONs exported!" }
    }
      
} else {
    if ($loggingEnabled) { logMessage "No include or exclude defined, quitting!" }
    Write-Host "No include or exclude defined. Please check!" -ForegroundColor Red
    exit
}
