### Example script to get estimate for license consumers from cluster or helios - Jussi Jaurola <jussi@cohesity.com>

### Note! You need to have cohesity-api.ps1 on same directory!

### process commandline arguments
[CmdletBinding()]
param (
    [Parameter(Mandatory = $True)][string]$apikey,
    [Parameter()][ValidateSet('MB','GB','TB')][string]$unit = "GB",
    [Parameter(Mandatory = $False)][string]$clusterName,  
    [Parameter(Mandatory = $true)][string]$export 
    )


### source the cohesity-api helper code 
. ./cohesity-api.ps1

if ($clusterName) {
	try {
		apiauth -vip $clusterName -useApikey -password $apikey
	} catch {
    		write-host "Cannot connect to $($clusterName). Please check the apikey!" -ForegroundColor Red
    		exit
	}
} else { 
	try {
		apiauth -helios -password $apikey
	} catch {
    		write-host "Cannot connect to Helios. Please check the apikey!" -ForegroundColor Red
    		exit
	}
}

### Add headers to export-file
Add-Content -Path $export -Value "Cluster Name, DataProtect SVC Used ($unit), DataProtect Replica SVC Used ($unit), SmartFIles SVC Used ($unit)"

$units = "1" + $unit
if (!$clusterName) {
    ### Using Helios connection
	$clusters = (heliosClusters).name

	foreach ($cluster in $clusters) {
		## Connect to cluster
    	Write-Host "Connecting to cluster $cluster" -ForegroundColor Yellow

    	heliosCluster $cluster

    	$backupStats = api get "stats/consumers?maxCount=10000&fetchViewBoxName=true&fetchTenantName=true&fetchProtectionEnvironment=true&consumerType=kProtectionRuns"
    	$viewStats = api get "stats/consumers?msecsBeforeCurrentTimeToCompare=604800000&maxCount=10000&fetchViewBoxName=true&fetchTenantName=true&fetchProtectionPolicy=true&fetchProtectionEnvironment=true&consumerType=kViews"
    	$replicationStats = api get "stats/consumers?msecsBeforeCurrentTimeToCompare=604800000&maxCount=10000&fetchViewBoxName=true&fetchTenantName=true&fetchProtectionPolicy=true&fetchProtectionEnvironment=true&consumerType=kReplicationRuns"
    
        $dataProtectServiceUsed = 0
        $dataProtectReplicaUsed = 0
        $smartfilesUsed = 0

        ### Collecting dataProtectService usages
        foreach ($stat in $backupStats.statsList) {
            $jobname = $stat.name
            Write-Host "    Collecting stats for $jobname" -ForegroundColor Yellow
            $dataProtectServiceUsed += $stat.stats.localDataWrittenBytes
        }

        ### Collecting dataProtectReplicaSVC usages
        foreach ($stat in $replicationStats.statsList) {
            Write-Host "    Collecting stats for $jobname" -ForegroundColor Yellow
            $dataProtectReplicaUsed += $stat.stats.localDataWrittenBytes
        }

        ### Collecting smartfilesSVC usages
        foreach ($stat in $viewStats.statsList) {
            Write-Host "    Collecting stats for $jobname" -ForegroundColor Yellow
            $smartfilesUsed += $stat.stats.localDataWrittenBytes
        }
        ### write data 
        $line = "{0},{1},{2},{3}" -f $cluster, [math]::Round($dataProtectServiceUsed/$units, 2), [math]::Round($dataProtectReplicaUsed/$units, 2), [math]::Round($smartfilesUsed/$units, 2)
Add-Content -Path $export -Value $line
    } 
} else {
    ### Using connection
    $backupStats = api get "stats/consumers?maxCount=10000&fetchViewBoxName=true&fetchTenantName=true&fetchProtectionEnvironment=true&consumerType=kProtectionRuns"
    $viewStats = api get "stats/consumers?msecsBeforeCurrentTimeToCompare=604800000&maxCount=10000&fetchViewBoxName=true&fetchTenantName=true&fetchProtectionPolicy=true&fetchProtectionEnvironment=true&consumerType=kViews"
    $replicationStats = api get "stats/consumers?msecsBeforeCurrentTimeToCompare=604800000&maxCount=10000&fetchViewBoxName=true&fetchTenantName=true&fetchProtectionPolicy=true&fetchProtectionEnvironment=true&consumerType=kReplicationRuns"
    
    $dataProtectServiceUsed = 0
    $dataProtectReplicaUsed = 0
    $smartfilesUsed = 0

    ### Collecting dataProtectService usages
    foreach ($stat in $backupStats.statsList) {
        $jobname = $stat.name
        Write-Host "    Collecting stats for $jobname" -ForegroundColor Yellow
        $dataProtectServiceUsed += $stat.stats.localDataWrittenBytes
    }

    ### Collecting dataProtectReplicaSVC usages
    foreach ($stat in $replicationStats.statsList) {
        Write-Host "    Collecting stats for $jobname" -ForegroundColor Yellow
        $dataProtectReplicaUsed += $stat.stats.localDataWrittenBytes
    }

    ### Collecting smartfilesSVC usages
    foreach ($stat in $viewStats.statsList) {
        Write-Host "    Collecting stats for $jobname" -ForegroundColor Yellow
        $smartfilesUsed += $stat.stats.localDataWrittenBytes
    }
    ### write data 
    $line = "{0},{1},{2},{3}" -f $cluster, [math]::Round($dataProtectServiceUsed/$units, 2), [math]::Round($dataProtectReplicaUsed/$units, 2), [math]::Round($smartfilesUsed/$units, 2)
Add-Content -Path $export -Value $line
}
