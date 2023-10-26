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

    Write-Host "    Getting Storage Consumers stats from $cluster" -ForegroundColor Yellow

    $replicationStats = api get "stats/consumers?maxCount=1000&fetchViewBoxName=true&fetchTenantName=true&fetchProtectionPolicy=true&fetchProtectionEnvironment=true&consumerType=kReplicationRuns"
    $viewStats = api get "stats/consumers?maxCount=1000&fetchViewBoxName=true&fetchTenantName=true&fetchProtectionEnvironment=true&consumerType=kViews"
    $viewProtetionStats = api get "stats/consumers?maxCount=1000&fetchViewBoxName=true&fetchTenantName=true&fetchProtectionEnvironment=true&consumerType=kViewProtectionRuns"
    $stats = api get "stats/consumers?maxCount=1000&fetchViewBoxName=true&fetchTenantName=true&fetchProtectionEnvironment=true&consumerType=kProtectionRuns"
    
    $tenants = $stats.statsList.groupList.tenantName | Sort-Object | Get-Unique

    if ($tenants) {
        Write-Host "    Collecting tenants stats" -ForegroundColor Yellow
    
        foreach ($tenant in $tenants) {
            
            $tenantStats = $stats.statsList | Where { $_.groupList.tenantName -eq $tenantName}
            $tenantReplicationStats = $replicationStats.statsList | Where { $_.groupList.tenantName -eq $tenantName}
            $tenantViewStats = $viewStats.statsList | Where { $_.groupList.tenantName -eq $tenantName}
            $tenantViewProtectionStats = $tenantViewProtectionStats.statsList | Where { $_.groupList.tenantName -eq $tenantName}
    
            if ($tenantStats) {
                $storageDomainName = $tenantStats[0].groupList.viewBoxName
            } elseif ($tenantReplicationStats) {
                $storageDomainName = $tenantReplicationStats[0].groupList.viewBoxName
            } elseif ($tenantViewStats) {
                $storageDomainName = $tenantViewStats[0].groupList.viewBoxName
            } 
    
            $totalReplStats = 0
            $totalViewStats = 0
            $tenantStorage = 0
    
            if ($tenantReplicationStats) {
                Write-host "    Found replication stats for $tenant" -ForegroundColor Yellow
                foreach ($tenantReplicationStat in $tenantReplicationStats) {
                    $totalReplStats += $tenantReplicationStat.stats.storageConsumedBytes
                }
            } else {
                Write-host "    No replication stats for $tenant" -ForegroundColor Red
            }
    
            if ($tenantViewStats) {
                Write-Host "    Found View stats for $tenant" -ForegroundColor Yellow
                foreach ($tenantViewStat in $tenantViewStats) {
                    $totalViewStats += $tenantReplicationStat.stats.storageConsumedBytes
                }
    
                foreach ($tenantViewProtectionStat in $tenantViewProtectionStats) {
                    $totalViewStats += $tenantViewProtectionStat.stats.storageConsumedBytes
                }
            } else {
                Write-Host "    No view stats for $tenant" -ForegroundColor Red
            }
    
            foreach ($tenantStat in $tenantStats) {
                $tenantStorage += $tenantStat.stats.storageConsumedBytes
            }
    
            # Export content for tenant
            $line = "{0},{1},{2},{3},{4},{5},{6}" -f $today, $cluster, $tenant, $storageDomainName, [math]::Round(($tenantStorage/$units),1), [math]::Round(($totalReplStats/$units),1), [math]::Round(($totalViewStats/$units),1)
            Add-Content -Path $export -Value $line
        }
    } else {
         Write-Host "    No tenant data found for $cluster" -ForegroundColor Red
    }
}




