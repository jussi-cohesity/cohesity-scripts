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
Add-Content -Path $export -Value "Cluster Name, Tenant Name, Protection Group, Environment Type, Source Count, Data In ($unit), Data In After Dedupe ($unit), Local Data Written ($unit), Cloud Data Written ($unit), Storage Consumed ($unit)"

### Get usage stats
$units = "1" + $unit
$stats = api get "stats/consumers?maxCount=1000&fetchViewBoxName=true&fetchTenantName=true&fetchProtectionEnvironment=true&consumerType=kProtectionRuns"
$jobs = api get protectionJobs
foreach ($stat in $stats.statsList) {

    $jobname = $stat.name
    $tenantName = $stat.groupList.tenantName
    $environment = $stat.protectionEnvironment
    
    $job = $jobs | Where { $_.name -eq $jobname }
    $sourceCount = (api get "protectionRuns?jobId=$($job.id)&numRuns=1").backupRun.sourceBackupStatus.count

    $dataIn = $stat.stats.dataInBytes/$units
    $dataInDeduped = $stat.stats.dataInBytesAfterDedup/$units
    $localDataWritten = $stat.stats.localDataWrittenBytes/$units
    $cloudDataWritten = $stat.stats.cloudDataWrittenBytes/$units
    $storageConsumed = $stat.stats.storageConsumedBytes/$units

    ### write data 
    $line = "{0},{1},{2},{3},{4},{5},{6},{7},{8},{9}" -f $clusterName, $tenantName, $jobName, $environment, $sourceCount, $dataIn, $dataInDeduped, $localDataWritten, $cloudDataWritten, $storageConsumed
    Add-Content -Path $export -Value $line
}
