### Example script include/exclude users with ADgroups, users with smtp-domains, sites or teams for M365 protection group - Jussi Jaurola <jussi@cohesity.com>

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
    [Parameter(Mandatory = $False)][array]$includeSites,
    [Parameter(Mandatory = $False)][array]$excludeSites,
    [Parameter(Mandatory = $False)][array]$includeTeams,
    [Parameter(Mandatory = $False)][array]$excludeTeams,
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
        Add-content -Path $logFileName -Value $Line
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
$availableSites = @{}

if ($loggingEnabled) { logMessage "Collecting allAvailableObjects" }
foreach ($availableUser in ($allAvailableObjects | Where { $_.office365ProtectionSource.type -eq 'kUser' })) {
    $emailAddress = $availableUser.office365ProtectionSource.primarySMTPAddress
    if ($emailAddress) {
        if (!$availableUsers[$emailAddress]) {
            $userId = $availableUser.id
            $availableUsers.Add($emailAddress, $userId)
            if ($loggingEnabled) { logMessage "    User $emailAddress added" }
        }
    }
}



$includeDefined = $False
$excludeDefined = $False

$excludeIds = [System.Collections.ArrayList]::new()
$includeIds = [System.Collections.ArrayList]::new()
$includeDomainUsers = [System.Collections.ArrayList]::new()
$excludeDomainUsers = [System.Collections.ArrayList]::new()

if ($excludeAds) {
    $excludeDefined = $True
    if ($loggingEnabled) { logMessage "Exclude AD(s) defined, getting users from AD(s)" }
    Write-Host "Exclude AD(s) defined" -ForegroundColor Yellow
    Write-Host "    Getting users from AD(s): $($excludeAds)" -ForegroundColor Yellow

    foreach ($excludeAd in $excludeAds) {
        $users = Get-ADUser -server $excludeAd -Filter * -Properties EmailAddress | Select EmailAddress

        foreach ($user in $users)
        {
            if ($user.EmailAddress) {

                if ($excludeSMTPdomains) {
                    $excludeDomainUsers.Add($user.EmailAddress) | out-null
                    if ($loggingEnabled) { logMessage "    Added $($user.EmailAddress) to excludeDomainUsers" }
                } else {
                    if ($availableUsers[$user.EmailAddress.ToString()]) {
                        $excludeIds.Add(($availableUsers[$user.EmailAddress])) | out-null
                        if ($loggingEnabled) { logMessage "    Added $($user.EmailAddress) to excludeIds" }
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

        foreach ($user in $users)
        {
            if ($user.EmailAddress) {
                if ($includeSMTPdomains) {
                    $includeDomainUsers.Add($user.EmailAddress) | out-null
                    if ($loggingEnabled) { logMessage "    Added $($user.EmailAddress) to includeDomainUsers" }
                } else {
                    if ($availableUsers[$user.EmailAddress.ToString()]) {
                        $includeIds.Add(($availableUsers[$user.EmailAddress])) | out-null
                        if ($loggingEnabled) { logMessage "    Added $($user.EmailAddress) to includeIds" }
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
        $adGroup = $excludeAdGroup -split "@"[0]
        $adDomain = $excludeAdGroup -split "@"[1]
        $users = Get-ADGroupMember -identity $adGroup -server $adDomain -Recursive | Get-ADUser -Properties EmailAddress | Select EmailAddress
    
        foreach ($user in $users) {
            if ($user.EmailAddress) {
                if ($excludeSMTPdomains) {
                    $excludeDomainUsers.Add($user.EmailAddress) | out-null
                    if ($loggingEnabled) { logMessage "    Added $($user.EmailAddress) to excludeDomainUsers" }
                } else {
                    if ($availableUsers[$user.EmailAddress.ToString()]) {
                        $excludeIds.Add(($availableUsers[$user.EmailAddress])) | out-null
                        if ($loggingEnabled) { logMessage "    Added $($user.EmailAddress) to excludeIds" }
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
        if ($excludeDomainUsers) {
            foreach ($excludeDomainUser in ($excludeDomainUsers | Where { $_ -match $excludeSMTPdomain })) {
                $userId = $availableUsers[$excludeDomainUser]
                if ($userId) {
                    $excludeIds.Add($userId) | out-null
                    if ($loggingEnabled) { logMessage "    Added $($excludeDomainUser) to excludeIds" }
                }
            }
        } else {
            if ($loggingEnabled) { logMessage "Filtering users with $excludeSMTPdomain" }
            $users = $allAvailableObjects | Where { $_.office365ProtectionSource.type -eq 'kUser' } | Where { $_.office365ProtectionSource.primarySMTPAddress -match $($excludeSMTPdomain) }
            if ($loggingEnabled) { logMessage "    Found $($users.count) users matching domain $excludeSMTPdomain" }
            
            foreach ($user in $users) {
                $excludeIds.Add($user.id) | out-null
                if ($loggingEnabled) { logMessage "    Added $($user.EmailAddress) to excludeIds" }
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
        $adGroup = $includeAdGroup -split "@"[0]
        $adDomain = $includeAdGroup -split "@"[1]
        $users = Get-ADGroupMember -identity $adGroup -server $adDomain -Recursive | Get-ADUser -Properties EmailAddress | Select EmailAddress
    
        foreach ($user in $users) {
            if ($includeSMTPdomains) {
                    $includeDomainUsers.Add($user.EmailAddress) | out-null
                    if ($loggingEnabled) { logMessage "    Added $($user.emailAddress) to includeDomainUsers" }
            } else {
                $includeIds.Add(($availableUsers[$user.EmailAddress])) | out-null
                if ($loggingEnabled) { logMessage "    Added $($user.EmailAddress) to excludeIds" }
            }
        }
    }
}

if ($includeSMTPdomains) {
    $includeDefined = $True

    if ($loggingEnabled) { logMessage "Include SMTP domains defined, collecting users from domain(s)" }
    Write-Host "Include SMTP domains defined" -ForegroundColor Yellow
    Write-Host "    Getting users from domain(s): $($includeSMTPdomains)" -ForegroundColor Yellow

    foreach ($includeSMTPdomain in $includeSMTPdomains) {
        if ($includeDomainUsers) {
            foreach ($includeDomainUser in ($includeDomainUsers | Where { $_ -match $includeSMTPdomain })) {
                $userId = $availableUsers[$includeDomainUser]
                if ($userId) { 
                    $includeIds.Add($userId) | out-null
                    if ($loggingEnabled) { logMessage "    Added $($includeDomainUser) to includeIds" }
                } 
            }
        } else {
            if ($loggingEnabled) { logMessage "Filtering users with $excludeSMTPdomain" }
            $users = $allAvailableObjects | Where { $_.office365ProtectionSource.type -eq 'kUser' } | Where { $_.office365ProtectionSource.primarySMTPAddress -match $($includeSMTPdomain) }
            if ($loggingEnabled) { logMessage "    Found $($users.count) users matching domain $excludeSMTPdomain" }
            
            foreach ($user in $users) {
                $includeIds.Add($user.id) | out-null
                if ($loggingEnabled) { logMessage "    Added $($user.EmailAddress) to includeIds" }
            }
        }
    }
}

if ($includeSites) {
    $includeDefined = $True

    if ($loggingEnabled) { logMessage "Include sites defined" }
    Write-Host "Including sites defined" -ForegroundColor Yellow
    Write-Host "    Getting IDs for site(s): $($includeSites)" -ForegroundColor

    foreach ($includeSite in $includeSites) {
        $site = $allAvailableObjects | Where { $_.office365ProtectionSource.type -eq 'kSite' } | Where { $_.office365ProtectionSource.name -match $($includeSite) }
        $includeIds.Add($site.id) | out-null
        if ($loggingEnabled) { logMessage "    Added $($site.id) to includeIds" }
    }

}

if ($excludeSites) {
    $excludeDefined = $True

    if ($loggingEnabled) { logMessage "Exclude sites defined" }
    Write-Host "Excluding sites defined" -ForegroundColor Yellow
    Write-Host "    Getting IDs for site(s): $($excludeSites)" -ForegroundColor Yellow

    foreach ($excludeSite in $excludeSites) {
        $site = $allAvailableObjects | Where { $_.office365ProtectionSource.type -eq 'kSite' } | Where { $_.office365ProtectionSource.name -match $($excludeSite) }
        $excludeIds.Add($site.id) | out-null
        if ($loggingEnabled) { logMessage "    Added $($site.id) to excludeIds" }
    }

}

if ($includeTeams) {
    $includeDefined = $True

    if ($loggingEnabled) { logMessage "Include teams defined" }
    Write-Host "Including teams defined" -ForegroundColor Yellow
    Write-Host "    Getting IDs for teams(s): $($includeTeams)" -ForegroundColor

    foreach ($includeTeam in $includeTeams) {
        $teams = $allAvailableObjects | Where { $_.office365ProtectionSource.type -eq 'kTeam' } | Where { $_.office365ProtectionSource.name -match $($includeTeam) }
        $includeIds.Add($teams.id) | out-null
        if ($loggingEnabled) { logMessage "    Added $($teams.id) to includeIds" }
    }

}

if ($excludeTeams) {
    $excludeDefined = $True

    if ($loggingEnabled) { logMessage "Exclude teams defined" }
    Write-Host "Excluding teams defined" -ForegroundColor Yellow
    Write-Host "    Getting IDs for teams(s): $($excludeTeams)" -ForegroundColor

    foreach ($includeTeam in $includeTeams) {
        $teams = $allAvailableObjects | Where { $_.office365ProtectionSource.type -eq 'kTeam' } | Where { $_.office365ProtectionSource.name -match $($excludeTeam) }
        $excludeIds.Add($teams.id) | out-null
        if ($loggingEnabled) { logMessage "    Added $($teams.id) to excludeIds" }
    }
    
}

if (($includeDefined) -or ($excludeDefined)) {
    if ($loggingEnabled) { logMessage "Getting information for ProtectionGroup $protectionGroup" }
    Write-Host "Getting information for ProtectionGroup $protectionGroup" -ForegroundColor Yellow
    $job = Get-CohesityProtectionJob -Names $protectionGroup
    if ($loggingEnabled) { logMessage "ProtectionGroup details collected" }
    Write-Host "Updating ProtectionGroup $protectionGroup" -ForegroundColor Yellow
    
    if ($includeIds) {
        if ($loggingEnabled) { logMessage "Including $($includeIds.count) objects" }
        Write-Host "    Including $($includeIds.count) objects" -ForegroundColor Yellow
        if ($job.sourceIds) {
            $job.sourceIds = $includeIds | Sort | Get-Unique
            if ($loggingEnabled) { logMessage "Job includeIds updated" }
        } else {
            $job | Add-Member -Membertype NoteProperty -Name "sourceIds" -Value ($includeIds | Sort | Get-Unique)
            if ($loggingEnabled) { logMessage "Job includeId added" }
        }
    }

    if ($excludeIds) {
        if ($loggingEnabled) { logMessage "Excluding $($excludeIds.count) objects" }
        Write-Host "    Excluding $($excludeIds.count) objects" -ForegroundColor Yellow
        if ($job.excludeSourceIds) {
            $job.excludeSourceIds = $excludeIds | Sort | Get-Unique
            if ($loggingEnabled) { logMessage "Job excludeIds updated" }
        } else {
            $job | Add-Member -Membertype NoteProperty -Name "excludeSourceIds" -Value ($excludeIds | Sort | Get-Unique)
            if ($loggingEnabled) { logMessage "Job excludeIds added" }
        }
    }

    if (!$debugOnly) {
        if ($loggingEnabled) { logMessage "Updating job to cluster" }
        Set-CohesityProtectionJob -ProtectionJob $job -Confirm:$false 
        if ($loggingEnabled) { logMessage "Job updated" }
    } else {
        if ($loggingEnabled) { logMessage "Debug enabled, no actual job run but exporting JSONs" }
        Write-host "Debug enabled. Dumping variables to json only!" -ForegroundColor Yellow
    
        $job | ConvertTo-Json -depth 15 | Out-file job.json
        $includeIds | ConvertTo-Json -depth 15 | Out-file includeIds.json
        $excludeIds | ConvertTo-Json -depth 15 | Out-File excludeIds.json
        $source | Convertto-Json -depth 15 | Out-File source.json
        $allAvailableObjects | ConvertTo-Json -depth 15 | Out-File allAvailableObjects.json
        $availableUsers | ConvertTo-Json -depth 15 | Out-File availableUsers.json
        $includeDomainUsers | ConvertTo-Json -depth 15 | Out-File includeDomainUsers.json
        $excludeDomainUsers | ConvertTo-Json -depth 15 | Out-File excludeDomainUsers.json
        if ($loggingEnabled) { logMessage "JSONs exported!" }
    }
      
} else {
    if ($loggingEnabled) { logMessage "No include or exclude defined, quitting!" }
    Write-Host "No include or exclude defined. Please check!" -ForegroundColor Red
    exit
}
