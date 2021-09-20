### Example script to get estimate for license consumers from helios - Jussi Jaurola <jussi@cohesity.com>

### Note! You need to have cohesity-api.ps1 on same directory!

### process commandline arguments
[CmdletBinding()]
param (
    [Parameter(Mandatory = $True)][string]$apikey,
    [Parameter()][ValidateSet('MB','GB','TB')][string]$unit = "MB",
    [Parameter(Mandatory = $true)][string]$export 
    )


### source the cohesity-api helper code 
. ./cohesity-api.ps1

try {
    apiauth -helios -password $apikey
} catch {
    write-host "Cannot connect to Helios. Please check the apikey!" -ForegroundColor Red
    exit
}

### Add headers to export-file
Add-Content -Path $export -Value "Cluster Name, Tenant Name, Consumer, Environment Type, DataPlatform Used ($unit), DataProtect Used ($unit), CloudArchive Used ($unit)"

$units = "1" + $unit

$clusters = $HELIOSCONNECTEDCLUSTERS.name
foreach ($cluster in $clusters) {
    ## Conenct to cluster
    Write-Host "Connecting to cluster $cluster" -ForegroundColor Yellow

    heliosCluster $cluster
    
    $backupStats = api get "stats/consumers?maxCount=10000&fetchViewBoxName=true&fetchTenantName=true&fetchProtectionEnvironment=true&consumerType=kProtectionRuns"
    $viewStats = api get "stats/consumers?msecsBeforeCurrentTimeToCompare=604800000&maxCount=10000&fetchViewBoxName=true&fetchTenantName=true&fetchProtectionPolicy=true&fetchProtectionEnvironment=true&consumerType=kViews"
    $replicationStats = api get "stats/consumers?msecsBeforeCurrentTimeToCompare=604800000&maxCount=10000&fetchViewBoxName=true&fetchTenantName=true&fetchProtectionPolicy=true&fetchProtectionEnvironment=true&consumerType=kReplicationRuns"

    foreach ($stat in $backupStats.statsList) {

        $jobname = $stat.name
        Write-Host "    Collecting stats for $jobname" -ForegroundColor Yellow

        $tenantName = $stat.groupList.tenantName
        $environment = $stat.protectionEnvironment

        $localStorageConsumed = $stat.stats.localDataWrittenBytes/$units
        $archiveStorageConsumed = $stat.stats.cloudTotalPhysicalUsageBytes/$units

        ### write data 
        $line = "{0},{1},{2},{3},{4},{5},{6}" -f $cluster, $tenantName, $jobName, $environment, $localStorageConsumed, $localStorageConsumed, $archiveStorageConsumed
        Add-Content -Path $export -Value $line
    }
    
    foreach ($stat in $viewStats.statsList) {
        
        $dataProtectUsed = 0
        
        $consumerName = $stat.name
        Write-Host "    Collecting stats for $jobname" -ForegroundColor Yellow
        
        $tenantName = $stat.groupList.tenantName
        $environment = $stat.groupList.consumer.type
        
        $localStorageConsumed = $stat.stats.localDataWrittenBytes/$units
        $archiveStorageConsumed = $stat.stats.cloudTotalPhysicalUsageBytes/$units
        
        ### write data 
        $line = "{0},{1},{2},{3},{4},{5},{6}" -f $cluster, $tenantName, $consumerName, $environment, $localStorageConsumed, $dataProtectUsed, $archiveStorageConsumed
        Add-Content -Path $export -Value $line
    }
    
    foreach ($stat in $replicationStats.statsList) {

        $dataProtectUsed = 0
        
        $jobname = $stat.name
        Write-Host "    Collecting stats for $jobname" -ForegroundColor Yellow

        $tenantName = $stat.groupList.tenantName
        $environment = $stat.protectionEnvironment

        $localStorageConsumed = $stat.stats.localDataWrittenBytes/$units
        $archiveStorageConsumed = $stat.stats.cloudTotalPhysicalUsageBytes/$units

        ### write data 
        $line = "{0},{1},{2},{3},{4},{5},{6}" -f $cluster, $tenantName, $jobName, $environment, $localStorageConsumed, $dataProtectUsed, $archiveStorageConsumed
        Add-Content -Path $export -Value $line
    }
    
}
