### Example script to get storage consumers from helios - Jussi Jaurola <jussi@cohesity.com>

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
Add-Content -Path $export -Value "Cluster Name, Tenant Name, Protection Group, Protection Policy, Environment Type, Source Object Count, Data In ($unit), Data In After Dedupe ($unit), Local Storage Consumed ($unit), Cloud Storage Consumed ($unit), Total Storage Consumed ($unit)"

### Get usage stats
$units = "1" + $unit

$clusters = heliosClusters | Select-Object -Property name

foreach ($cluster in $clusters.name) {
    ## Conenct to cluster
    Write-Host "Connecting cluster $cluster" -ForegroundColor Yellow
    heliosCluster $cluster

    Write-Host "    Getting Storage Consumers stats" -ForegroundColor Yellow
    $stats = api get "stats/consumers?maxCount=1000&fetchViewBoxName=true&fetchTenantName=true&fetchProtectionEnvironment=true&consumerType=kProtectionRuns"
    Write-Host "    Getting Protection Groups" -ForegroundColor Yellow
    $jobs = api get protectionJobs
    Write-Host "    Getting Protection Policies" -ForegroundColor Yellow
    $policies = api get protectionPolicies

    foreach ($stat in $stats.statsList) {
        $jobname = $stat.name
        Write-Host "        Getting stats for Protection Group $jobName" -ForegroundColor Yellow

        $tenantName = $stat.groupList.tenantName
        $environment = $stat.protectionEnvironment
        $job = $jobs | Where { $_.name -eq $jobname }
        $sourceCount = (api get "protectionRuns?jobId=$($job.id)&numRuns=1").backupRun.sourceBackupStatus.count

        $dataIn = [math]::Round(($stat.stats.dataInBytes/$units),1)
        $dataInDeduped = [math]::Round(($stat.stats.dataInBytesAfterDedup/$units),1)
        $localStorageConsumed = [math]::Round(($stat.stats.localTotalPhysicalUsageBytes/$units),1)
        $cloudStorageConsumed = [math]::Round(($stat.stats.cloudTotalPhysicalUsageBytes/$units),1)
        $totalStorageConsumed = [math]::Round(($stat.stats.storageConsumedBytes/$units),1)

        $policyName = ($policies | Where { $_.Id -eq $($job.policyId) }).name

        ### write data 
        $line = "{0},{1},{2},{3},{4},{5},{6},{7},{8},{9},{10}" -f $cluster, $tenantName, $jobName, $policyName, $environment, $sourceCount, $dataIn, $dataInDeduped, $localStorageConsumed, $cloudStorageConsumed, $totalStorageConsumed
        Add-Content -Path $export -Value $line
    }
}
