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
Add-Content -Path $export -Value "Cluster Name, Tenant Name, Consumer, Environment Type, DataPlatform Used ($unit), DataProtect Used ($unit), CloudArchive Used ($unit), DataProtect SVC Used ($unit), DataProtect Replica SVC Used ($unit), SmartFIles SVC Used ($unit)"

$units = "1" + $unit
$clusters = (heliosClusters).name

foreach ($cluster in $clusters) {
    ## Conenct to cluster
    Write-Host "Connecting to cluster $cluster" -ForegroundColor Yellow

    heliosCluster $cluster

    Write-Host "Checking cluster licensing method" -ForegroundColor Yellow

    $serviceLicensing = (api get /nexus/license/account_usage).featureOverusage | Where { $_.featureName -eq 'dataProtectService' }
    $backupStats = api get "stats/consumers?maxCount=10000&fetchViewBoxName=true&fetchTenantName=true&fetchProtectionEnvironment=true&consumerType=kProtectionRuns"
    $viewStats = api get "stats/consumers?msecsBeforeCurrentTimeToCompare=604800000&maxCount=10000&fetchViewBoxName=true&fetchTenantName=true&fetchProtectionPolicy=true&fetchProtectionEnvironment=true&consumerType=kViews"
    $replicationStats = api get "stats/consumers?msecsBeforeCurrentTimeToCompare=604800000&maxCount=10000&fetchViewBoxName=true&fetchTenantName=true&fetchProtectionPolicy=true&fetchProtectionEnvironment=true&consumerType=kReplicationRuns"
    
    if ($serviceLicensing) {
        Write-Host "Cluster is using SVC based licensing. Collecting usage metrics." -ForegroundColor Yellow
        
        ### Collecting dataProtectService usages
        foreach ($stat in $backupStats.statsList) {
            $dataProtectUsed = 0
            $dataPlatformUsed = 0
            $cloudArchiveUsed = 0
            $dataProtectServiceUsed = 0
            $dataProtectReplicaUsed = 0
            $smartfilesUsed = 0

            $jobname = $stat.name
            Write-Host "    Collecting stats for $jobname" -ForegroundColor Yellow

            $tenantName = $stat.groupList.tenantName
            $environment = $stat.protectionEnvironment

            $dataProtectServiceUsed = [math]::Round($stat.stats.localDataWrittenBytes/$units, 2)

            ### write data 
            $line = "{0},{1},{2},{3},{4},{5},{6},{7},{8},{9}" -f $cluster, $tenantName, $jobName, $environment, $dataPlatformUsed, $dataProtectUsed, $cloudArchiveUsed, $dataProtectServiceUsed, $dataProtectReplicaUsed, $smartfilesUsed
            Add-Content -Path $export -Value $line
        }

        ### Collecting dataProtectReplicaSVC usages
        foreach ($stat in $replicationStats.statsList) {
            $dataProtectUsed = 0
            $dataPlatformUsed = 0
            $cloudArchiveUsed = 0
            $dataProtectServiceUsed = 0
            $dataProtectReplicaUsed = 0
            $smartfilesUsed = 0

            $jobname = $stat.name
            Write-Host "    Collecting stats for $jobname" -ForegroundColor Yellow

            $tenantName = $stat.groupList.tenantName
            $environment = $stat.protectionEnvironment

            $dataProtectReplicaUsed = [math]::Round($stat.stats.localDataWrittenBytes/$units, 2)

            ### write data 
            $line = "{0},{1},{2},{3},{4},{5},{6},{7},{8},{9}" -f $cluster, $tenantName, $jobName, $environment, $dataPlatformUsed, $dataProtectUsed, $cloudArchiveUsed, $dataProtectServiceUsed, $dataProtectReplicaUsed, $smartfilesUsed
            Add-Content -Path $export -Value $line
        }

        ### Collecting smartfilesSVC usages
        foreach ($stat in $viewStats.statsList) {
            $dataProtectUsed = 0
            $dataPlatformUsed = 0
            $cloudArchiveUsed = 0
            $dataProtectServiceUsed = 0
            $dataProtectReplicaUsed = 0
            $smartfilesUsed = 0

            $jobname = $stat.name
            Write-Host "    Collecting stats for $jobname" -ForegroundColor Yellow

            $tenantName = $stat.groupList.tenantName
            $environment = $stat.protectionEnvironment

            $smartfilesUsed = [math]::Round($stat.stats.localDataWrittenBytes/$units, 2)

            ### write data 
            $line = "{0},{1},{2},{3},{4},{5},{6},{7},{8},{9}" -f $cluster, $tenantName, $jobName, $environment, $dataPlatformUsed, $dataProtectUsed, $cloudArchiveUsed, $dataProtectServiceUsed, $dataProtectReplicaUsed, $smartfilesUsed
            Add-Content -Path $export -Value $line
        }

    } else {
        Write-Host "Cluster is using old subscription based licensing. Collecting usage metrics." -ForegroundColor Yellow

        foreach ($stat in $backupStats.statsList) {

            $dataProtectUsed = 0
            $dataPlatformUsed = 0
            $cloudArchiveUsed = 0
            $dataProtectServiceUsed = 0
            $dataProtectReplicaUsed = 0
            $smartfilesUsed = 0
    
            $jobname = $stat.name
            Write-Host "    Collecting stats for $jobname" -ForegroundColor Yellow
    
            $tenantName = $stat.groupList.tenantName
            $environment = $stat.protectionEnvironment
    
            $dataProtectUsed = [math]::Round($stat.stats.localDataWrittenBytes/$units, 2)
            $dataPlatformUsed = [math]::Round($stat.stats.localDataWrittenBytes/$units, 2)
            $cloudArchiveUsed = [math]::Round($stat.stats.cloudTotalPhysicalUsageBytes/$units, 2)
    
            ### write data 
            $line = "{0},{1},{2},{3},{4},{5},{6},{7},{8},{9}" -f $cluster, $tenantName, $jobName, $environment, $dataPlatformUsed, $dataProtectUsed, $cloudArchiveUsed, $dataProtectServiceUsed, $dataProtectReplicaUsed, $smartfilesUsed
            Add-Content -Path $export -Value $line
        }
        
        foreach ($stat in $viewStats.statsList) {
            
            $dataProtectUsed = 0
            $dataPlatformUsed = 0
            $cloudArchiveUsed = 0
            $dataProtectServiceUsed = 0
            $dataProtectReplicaUsed = 0
            $smartfilesUsed = 0
            
            $consumerName = $stat.name
            Write-Host "    Collecting stats for $jobname" -ForegroundColor Yellow
            
            $tenantName = $stat.groupList.tenantName
            $environment = $stat.groupList.consumer.type
            
            $dataPlatformUsed = [math]::Round($stat.stats.localDataWrittenBytes/$units, 2)
            $cloudArchiveUsed = [math]::Round($stat.stats.cloudTotalPhysicalUsageBytes/$units, 2)
            
             ### write data 
             $line = "{0},{1},{2},{3},{4},{5},{6},{7},{8},{9}" -f $cluster, $tenantName, $jobName, $environment, $dataPlatformUsed, $dataProtectUsed, $cloudArchiveUsed, $dataProtectServiceUsed, $dataProtectReplicaUsed, $smartfilesUsed
             Add-Content -Path $export -Value $line
       }
        
        foreach ($stat in $replicationStats.statsList) {
    
            $dataProtectUsed = 0
            $dataPlatformUsed = 0
            $cloudArchiveUsed = 0
            $dataProtectServiceUsed = 0
            $dataProtectReplicaUsed = 0
            $smartfilesUsed = 0
            
            $jobname = $stat.name
            Write-Host "    Collecting stats for $jobname" -ForegroundColor Yellow
    
            $tenantName = $stat.groupList.tenantName
            $environment = $stat.protectionEnvironment
    
            $dataPlatformUsed = [math]::Round($stat.stats.localDataWrittenBytes/$units, 2)
            $cloudArchiveUsed = [math]::Round($stat.stats.cloudTotalPhysicalUsageBytes/$units, 2)
    
            ### write data 
            $line = "{0},{1},{2},{3},{4},{5},{6},{7},{8},{9}" -f $cluster, $tenantName, $jobName, $environment, $dataPlatformUsed, $dataProtectUsed, $cloudArchiveUsed, $dataProtectServiceUsed, $dataProtectReplicaUsed, $smartfilesUsed
            Add-Content -Path $export -Value $line
 
        }
    } 
}
