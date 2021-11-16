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

### Get audit report
$clusters = (heliosClusters).name

foreach ($cluster in $clusters) {
    ## Conenct to cluster
    Write-Host "Connecting to cluster $cluster" -ForegroundColor Yellow
    
    heliosCluster $cluster

    $sources = api get protectionSources?environments=kO365

    foreach($source in $sources) {
        $protectedObjects = api get "protectionSources/protectedObjects?id=$($source.protectionSource.id)&environment=kO365"
        $users = $protectedObjects | Where { $_.protectionSource.office365ProtectionSource.type -eq 'kUser'}
        $sites = $protectedObjects | Where { $_.protectionSource.office365ProtectionSource.type -eq 'kSite'}
        $teams = $protectedObjects | Where { $_.protectionSource.office365ProtectionSource.type -eq 'kTeam'}

        ### Collect Exchange and OneDrive sizes for each user
        $report = @{}
        foreach($user in $users) {
            $username = $($user.protectionSource.office365ProtectionSource.primarySMTPAddress)
            $customername = (($user.protectionJobs | Where { $_.name -match 'Mailbox' }).name).split(" - ")[0]
            $report[$username] = @{}
            $report[$username]['mailboxSize'] = $($user.protectionSource.office365ProtectionSource.userInfo.mailboxSize)
            $report[$username]['oneDriveSize'] = $($user.protectionSource.office365ProtectionSource.userInfo.oneDriveSize)  
            $report[$username]['oneDriveGroupName'] = ($user.protectionJobs | Where { $_.name -match 'Onedrive' }).name
            $report[$username]['exchangeGroupName'] = ($user.protectionJobs | Where { $_.name -match 'Mailbox' }).name
            $report[$username]['customername'] = $customername
        }

        foreach ($site in $sites) {
            $sitename = $($site.protectionSource.name)
            $customername = ($site.protectionJobs.name).split("-")[0]
            $report[$sitename] = @{}
            $report[$sitename]['siteGroupName'] = $($site.protectionJobs.name)
            $report[$sitename]['siteSize'] = $($site.stats.protectedSize)
            $report[$sitename]['customername'] = $customername
        }
    }
}

### Add headers to export-file
Add-Content -Path $export -Value "Customer, Consumer, Exchange Protection Group, Exchange Size, OneDrive Protection Group, OneDrive Size, Sites Protection Group Name, Sites Size"

### Export data
Write-Host "Exporting data..." -ForegroundColor Yellow

$report.GetEnumerator() | Sort-Object -Property {$_.Name} | ForEach-Object {
    $line = "{0},{1},{2},{3},{4},{5},{6},{7}" -f $_.Value.customername, $_.Name, $_.Value.exchangeGroupName, $_.Value.mailboxSize, $_.Value.oneDriveGroupName, $_.Value.oneDriveSize, $_.Value.siteGroupName, $_.Value.siteSize
    Add-Content -Path $export -Value $line
}
