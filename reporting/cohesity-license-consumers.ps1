### Example script to get cluster stats from helios - Jussi Jaurola <jussi@cohesity.com>

### Note! You need to have cohesity-api.ps1 on same directory!

### Data values are in TIB base2

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
    write-host "Cannot connect to Helios. Please check the apikey!" -ForegroundColor Yellow
    exit
}

### Add headers to export-file
Add-Content -Path $export -Value "Cluster Name, Tenant Name, Protection Group, Environment Type, Local Storage Consumed ($unit), Archive Storage Consumed ($unit)"

$units = "1" + $unit

$clusters = $HELIOSCONNECTEDCLUSTERS.name
foreach ($cluster in $clusters) {
    ## Conenct to cluster
    heliosCluster $cluster
    
    $stats = api get "stats/consumers?maxCount=10000&fetchViewBoxName=true&fetchTenantName=true&fetchProtectionEnvironment=true&consumerType=kProtectionRuns"

    foreach ($stat in $stats.statsList) {

        $jobname = $stat.name
        $tenantName = $stat.groupList.tenantName
        $environment = $stat.protectionEnvironment

        $localStorageConsumed = $stat.stats.storageConsumedBytes/$units
        $archiveStorageConsumed = $stat.stats.localDataWrittenBytes/$units

        ### write data 
        $line = "{0},{1},{2},{3},{4}" -f $clusterName, $tenantName, $jobName, $environment, $localStorageConsumed, $archiveStorageConsumed
        Add-Content -Path $export -Value $line
    }
}
