### Example script to provide storage consumed details per org - Jussi Jaurola <jussi@cohesity.com>

### Note! You need to have cohesity-api.ps1 on same directory!


### process commandline arguments
[CmdletBinding()]
param (
    [Parameter(Mandatory = $True)][string]$apikey,
    [Parameter()][ValidateSet('MB','GB','TB')][string]$unit = "GB",
    [Parameter(Mandatory = $true)][string]$export

    )

### source the cohesity-api helper code 
. $(Join-Path -Path $PSScriptRoot -ChildPath cohesity-api.ps1)

try {
    apiauth -helios -password $apikey
} catch {
    write-host "Cannot connect to Helios with key $apikey" -ForegroundColor Yellow
    exit
}

### Add headers to export-file

Add-Content -Path $export -Value "Date, Cluster Name, Organisation Name, Storage Domain Name, Storage Consumed ($unit), Storage Consumed Replicated ($unit), Storage Consumed SmartFiles($unit)"

### Get usage stats
$units = "1" + $unit
$report = @{}

$clusters = heliosClusters | Select-Object -Property name
$today = Get-Date -Format "dd.MM.yyyy"

foreach ($cluster in $clusters.name) {
    # Connect to cluster
    Write-Host "Connecting cluster $cluster" -ForegroundColor Yellow
    heliosCluster $cluster

    Write-Host "    Getting Storage Consumers stats" -ForegroundColor Yellow

    $replicationStats = api get "stats/consumers?maxCount=1000&fetchViewBoxName=true&fetchTenantName=true&fetchProtectionPolicy=true&fetchProtectionEnvironment=true&consumerType=kReplicationRuns"
    $viewStats = api get "stats/consumers?maxCount=1000&fetchViewBoxName=true&fetchTenantName=true&fetchProtectionEnvironment=true&consumerType=kViews"
    $viewProtetionStats = api get "stats/consumers?maxCount=1000&fetchViewBoxName=true&fetchTenantName=true&fetchProtectionEnvironment=true&consumerType=kViewProtectionRuns"
    $stats = api get "stats/consumers?maxCount=1000&fetchViewBoxName=true&fetchTenantName=true&fetchProtectionEnvironment=true&consumerType=kProtectionRuns"
    
    $tenants = api get tenants

    foreach ($tenant in $tenants) {
        $tenantName = $tenant.name
        $tenantStats = $stats.statsList | Where { $_.groupList.tenantName -eq $tenantName}
        $tenantReplicationStats = $replicationStats.statsList | Where { $_.groupList.tenantName -eq $tenantName}
        $tenantViewStats = $viewStats.statsList | Where { $_.groupList.tenantName -eq $tenantName}
        $tenantViewProtectionStats = $tenantViewProtectionStats.statsList | Where { $_.groupList.tenantName -eq $tenantName}


        $storageDomainName = $tenantStats[0].groupList.viewBoxName

        $totalReplStats = 0
        $totalViewStats = 0
        $tenantStorage = 0

        foreach ($tenantReplicationStat in $tenantReplicationStats) {
            $totalReplStats += $tenantReplicationStat.stats.storageConsumedBytes
        }

        foreach ($tenantViewStat in $tenantViewStats) {
            $totalViewStats += $tenantReplicationStat.stats.storageConsumedBytes
        }

        foreach ($tenantViewProtectionStat in $tenantViewProtectionStats) {
            $totalViewStats += $tenantViewProtectionStat.stats.storageConsumedBytes
        }

        foreach ($tenantStat in $tenantStats) {
            $tenantStorage += $tenantStat.stats.storageConsumedBytes
        }

        # Export content for tenant
        $line = "{0},{1},{2},{3},{4},{5},{6}" -f $today, $cluster, $storageDomainName, [math]::Round(($tenantStorage/$units),1), [math]::Round(($totalReplStats/$units),1), [math]::Round(($totalViewStats/$units),1)
        Add-Content -Path $export -Value $line
    }
}




