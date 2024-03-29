### Example script to report protected M365 source sizes - Jussi Jaurola <jussi@cohesity.com>

### Note! You need to have cohesity-api.ps1 on same directory! Script exports each clusters audit data to separate file to be sent to Cohesity

### process commandline arguments
[CmdletBinding()]
param (
    [Parameter(Mandatory = $True)][string]$apikey,
    [Parameter(Mandatory = $True)][string]$export
    )

### source the cohesity-api helper code 
. ./cohesity-api.ps1

try {
    apiauth -helios -password $apikey
} catch {
    write-host "Cannot connect to Helios. Please check the apikey!" -ForegroundColor Yellow
    exit
}

$clusters = (heliosClusters).name
$report = @{}
foreach ($cluster in $clusters) {
    ## Connect to cluster
    Write-Host "Connecting to cluster $cluster" -ForegroundColor Yellow
    
    heliosCluster $cluster

    Write-Host "   Getting sources for cluster $cluster" -ForegroundColor Yellow
    $sources = api get protectionSources?environments=kO365

    foreach($source in $sources) {
        Write-Host "     Collecting data for source $($source.protectionSource.name)" -ForegroundColor Yellow
        $protectedObjects = api get "protectionSources/protectedObjects?id=$($source.protectionSource.id)&environment=kO365"
        $users = $protectedObjects | Where { $_.protectionSource.office365ProtectionSource.type -eq 'kUser'}
        $sites = $protectedObjects | Where { $_.protectionSource.office365ProtectionSource.type -eq 'kSite'}
        $teams = $protectedObjects | Where { $_.protectionSource.office365ProtectionSource.type -eq 'kTeam'}

        ### Collect Exchange and OneDrive sizes for each user
        if ($users) {
            foreach($user in $users) {
                $username = $($user.protectionSource.office365ProtectionSource.primarySMTPAddress)
                $customername = (($user.protectionJobs[0]).name).split(" - ")[0]
                $report[$username] = @{}
                $report[$username]['mailboxSize'] = $($user.protectionSource.office365ProtectionSource.userInfo.mailboxSize)
                $report[$username]['oneDriveSize'] = $($user.protectionSource.office365ProtectionSource.userInfo.oneDriveSize)  
                $report[$username]['oneDriveGroupName'] = ($user.protectionJobs | Where { $_.name -match 'Onedrive' }).name
                $report[$username]['exchangeGroupName'] = ($user.protectionJobs | Where { $_.name -match 'Mailbox' }).name
                $report[$username]['customername'] = $customername
            }
        }

        if ($sites) {
            foreach ($site in $sites) {
                $sitename = $($site.protectionSource.name)
                $customername = ($site.protectionJobs.name).split("-")[0]
                $report[$sitename] = @{}
                $report[$sitename]['siteGroupName'] = $($site.protectionJobs.name)
                $report[$sitename]['siteSize'] = $($site.stats.protectedSize)
                $report[$sitename]['customername'] = $customername
            }
        }

        if ($teams) {
            foreach ($team in $teams) {
                $sitename = $($team.protectionSource.name)
                $customername = ($team.protectionJobs.name).split("-")[0]
                $report[$sitename] = @{}
                $report[$sitename]['teamGroupName'] = $($team.protectionJobs.name)
                $report[$sitename]['teamSize'] = $($team.stats.protectedSize)
                $report[$sitename]['customername'] = $customername
            }
        }
    }
}

### Add headers to export-file
Add-Content -Path $export -Value "Customer, Consumer, Exchange Protection Group, Exchange Size, OneDrive Protection Group, OneDrive Size, Sites Protection Group Name, Sites Size, Team Protection Group Name, Team Size"

### Export data
Write-Host "Exporting data..." -ForegroundColor Yellow

$report.GetEnumerator() | Sort-Object -Property {$_.Name} | ForEach-Object {
    $line = "{0},{1},{2},{3},{4},{5},{6},{7},{8},{9}" -f $_.Value.customername, $_.Name, $_.Value.exchangeGroupName, $_.Value.mailboxSize, $_.Value.oneDriveGroupName, $_.Value.oneDriveSize, $_.Value.siteGroupName, $_.Value.siteSize, $_.Value.teamGroupName, $_.Value.teamSize
    Add-Content -Path $export -Value $line
}
