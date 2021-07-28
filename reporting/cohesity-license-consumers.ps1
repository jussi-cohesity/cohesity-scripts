### Example script to get cluster stats from local clusters - Jussi Jaurola <jussi@cohesity.com

### Note! You need to have cohesity-api.ps1 on same directory!


### process commandline arguments
[CmdletBinding()]
param (
    [Parameter(Mandatory = $True)][string]$vip, 
    [Parameter(Mandatory = $True)][string]$username,
    [Parameter()][ValidateSet('MB','GB','TB')][string]$unit = "MB",
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
Add-Content -Path $export -Value "Cluster Name, Tenant Name, Protection Group, Environment Type, Storage Consumed ($unit)"

### Get usage stats
$units = "1" + $unit
$stats = api get "stats/consumers?maxCount=10000&fetchViewBoxName=true&fetchTenantName=true&fetchProtectionEnvironment=true&consumerType=kProtectionRuns"

foreach ($stat in $stats.statsList) {

    $jobname = $stat.name
    $tenantName = $stat.groupList.tenantName
    $environment = $stat.protectionEnvironment

    $storageConsumed = $stat.stats.storageConsumedBytes/$units

    ### write data 
    $line = "{0},{1},{2},{3},{4}" -f $clusterName, $tenantName, $jobName, $environment, $storageConsumed
    Add-Content -Path $export -Value $line
}
