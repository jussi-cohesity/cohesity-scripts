### Example script to get cluster stats from local clusters - Jussi Jaurola <jussi@cohesity.com

### Note! You need to have cohesity-api.ps1 on same directory!


### process commandline arguments
[CmdletBinding()]
param (
    [Parameter(Mandatory = $True)][string]$vip, 
    [Parameter(Mandatory = $True)][string]$username,
    [Parameter(Mandatory = $true)][string]$export 
    )

### source the cohesity-api helper code 
. ./cohesity-api.ps1

try {
    apiauth -vip $vip -username $username 
    $clusterName = (api get cluster).name
} catch {
    write-host "Cannot connect to cluster $vip" -ForegroundColor Yellow
    exit
}

### Add headers to export-file
Add-Content -Path $export -Value "Cluster Name, Tenant Name, Protection Group, Environment Type, Data In, Data In After Dedupe, Local Data Written, Cloud Data Written, Storage Consumed"

### Get usage stats

$stats = api get "stats/consumers?maxCount=1000&fetchViewBoxName=true&fetchTenantName=true&fetchProtectionEnvironment=true&consumerType=kProtectionRuns"

foreach ($stat in $stats.statsList) {

    $jobname = $stat.name
    $tenantName = $stat.groupList.tenantName
    $environment = $stat.protectionEnvironment

    $dataIn = $stat.stats.dataInBytes
    $dataInDeduped = $stat.stats.dataInBytesAfterDedup
    $localDataWritten = $stat.stats.localDataWrittenBytes
    $cloudDataWritten = $stat.stats.cloudDataWrittenBytes
    $storageConsumed = $stat.stats.storageConsumedBytes

    ### write data 
    $line = "{0},{1},{2},{3},{4},{5},{6},{7},{8}" -f $clusterName, $tenantName, $jobName, $environment, $dataIn, $dataInDeduped, $localDataWritten, $cloudDataWritten, $storageConsumed
    Add-Content -Path $export -Value $line
}
