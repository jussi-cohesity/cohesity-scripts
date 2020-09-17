
### Example script to get cluster stats from helios - Jussi Jaurola <jussi@cohesity.com>

### Note! You need to have cohesity-api.ps1 on same directory!


### process commandline arguments
[CmdletBinding()]
param (
    [Parameter(Mandatory = $True)][string]$apikey,
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


$clusters = $HELIOSCONNECTEDCLUSTERS.name
foreach ($cluster in $clusters) {
    ## Conenct to cluster
    heliosCluster $cluster

    ### Get clusterStorageConsumedBytes
    $clusterStats = api get "cluster?fetchTimeSeriesSchema=true&fetchStats=true"
    $clusterEntityId = $clusterStats.schemaInfoList[2].entityId
    $timeSeriesStats =  api get "statistics/timeSeriesStats?startTimeMsecs=1600214598804&schemaName=kBridgeClusterTierPhysicalStats&metricName=kMorphedUsageBytes&rollupIntervalSecs=21600&rollupFunction=latest&entityIdList=$clusterEntityId"
    $clusterStorageConsumedBytes = $timeSeriesStats.dataPointVec[0].data.int64Value

    ### Get clusterProtectedObjects and clusterProtectedObjectCapacity
    $protectionSources =api get "protectionSources/registrationInfo?includeEntityPermissionInfo=true"
    $clusterProtectedObjects = $protectionSources.stats.protectedCount
    $clusterProtectedCapacity = $protectionSources.stats.protectedSize

    if ($export) {
        ## write data 
        $line = "{0},{1},{2},{3}" -f $cluster, $clusterStorageConsumedBytes, $clusterProtectedObjects, $clusterProtectedCapacity
        Add-Content -Path $export -Value $line

    }
}
