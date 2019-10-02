### usage: ./capacityReport.ps1 -vip 192.168.1.198 -username admin [ -domain local ] -startDate 'mm/dd/yyyy' [-jobName 'Virtual'] [-runs '30'] [-export 'filename.csv'] [-unit MB/GB/TB] [-includeReplicatedJobs true|false]

### Capacity reporting example - Jussi Jaurola <jussi@cohesity.com>

### process commandline arguments
[CmdletBinding()]
param (
    [Parameter(Mandatory = $True)][string]$vip,
    [Parameter(Mandatory = $True)][string]$username,
    [Parameter()][string]$domain = 'local',
    [Parameter(Mandatory = $True)][string]$startDate,
    [Parameter()][string]$jobName,
    [Parameter()][string]$runs = '1000',
    [Parameter()][string]$export,
    [Parameter()][ValidateSet('MB','GB','TB')][string]$unit = "MB",
    [Parameter()][ValidateSet('true','false')][string]$includeReplicatedJobs = "false"
)


### source the cohesity-api helper code
. ./cohesity-api

### startDate to usecs
try {
    $startDate = dateToUsecs $startDate
} catch {
    write-host "Given startDate is not valid. Please use dd/mm/yyyyy" -ForegroundColor Yellow
    exit
}
### authenticate
apiauth -vip $vip -username $username -domain $domain

### cluster Id
$clusterId = (api get cluster).id

$csvcontent =""
### find protectionRuns 



"Collecting Job Run Statistics"

### Create filter based on params
###    $protectionJobs = (api get protectionJobs?allUnderHierarchy=true) | Where-Object{ $_.policyId.split(':')[0] -eq $clusterId }|Where name -match $jobName

$protectionJobs = (api get protectionJobs?allUnderHierarchy=true)
if ($includeReplicatedJobs -eq "false") { $protectionJobs = $protectionJobs | Where-Object{ $_.policyId.split(':')[0] -eq $clusterId }}
if ($jobName) { $protectionJobs = $protectionJobs | Where name -match $jobName  }

if (!$protectionJobs) {
    write-host "No jobruns found with given filters" -ForegroundColor Yellow
    exit
}

if ($export) {
    if ($unit -eq "MB"){Add-Content -Path $export -Value "'Source job','Source Size (MB)','Backup Size (MB)','Frontend Capacity (MB)','Backend Capacity (MB)','Archived Capacity (MB)','Tenant Name','Tenant ID','Source Cluster'"}
    if ($unit -eq "GB"){Add-Content -Path $export -Value "'Source job','Source Size (GB)','Backup Size (GB)','Frontend Capacity (GB)','Backend Capacity (GB)','Archived Capacity (MB)','Tenant Name','Tenant ID','Source Cluster'"}
    if ($unit -eq "TB"){Add-Content -Path $export -Value "'Source job','Source Size (TB)','Backup Size (TB)','Frontend Capacity (TB)','Backend Capacity (TB)','Archived Capacity (TB)','Tenant Name','Tenant ID','Source Cluster'"}
} 

foreach ($job in $protectionJobs) {
    "Runs for $($job.name)"
    $jobId = $job.id
    $jobName = $job.name

    $backupjobruns = api get /backupjobruns?id=$($jobid)`&allUnderHierarchy=true`&numRuns=$runs`&excludeTasks=true`&excludeNonRestoreableRuns=true`&startTimeUsecs=$startDate
    $run = $backupjobruns.backupJobRuns.protectionRuns.backupRun.base
    $tenantName = $backupjobruns.tenants.name
    $tenantId = $backupjobruns.tenants.tenantId

    if ($backupjobruns) { 
        
        ### Find remote cluster name
        $policyId = $job.policyId.split(':')[1]
        if ($policyId -ne $clusterId) {
            $remoteCluster = api get remoteClusters | where clusterIncarnationId -eq $policyId
            $remoteClusterName = $remoteCluster.name
            write-host "Job is remote. Original source $remoteClusterName"
        }

        ### Find CloudArchive capacity
        $iceboxArchiveBytes = $backupjobruns.backupJobRuns.protectionRuns.copyRun.finishedTasks.archivalInfo.bytesTransferred

        if ($unit -eq  "MB") {
            $run | Select-Object -Property @{Name="Run Date"; Expression={usecsToDate $_.startTimeUsecs}},
                                            @{Name="Source Size"; Expression={[math]::Round(($_.totalSourceSizeBytes)/(1024*1024))}},
                                            @{Name="Run Seconds"; Expression={[math]::Round(($_.endTimeUsecs - $_.startTimeUsecs)/(1000*1000))}},
                                            @{Name="MB Read"; Expression={[math]::Round(($_.totalBytesReadFromSource)/(1024*1024))}},
                                             @{Name="MB Written"; Expression={[math]::Round(($_.totalPhysicalBackupSizeBytes)/(1024*1024))}} | ft 
        }
        
        if ($unit -eq  "GB") {
            $run | Select-Object -Property @{Name="Run Date"; Expression={usecsToDate $_.startTimeUsecs}},
                                            @{Name="Source Size"; Expression={[math]::Round(($_.totalSourceSizeBytes)/(1024*1024*1024))}},
                                            @{Name="Run Seconds"; Expression={[math]::Round(($_.endTimeUsecs - $_.startTimeUsecs)/(1000*1000))}},
                                            @{Name="GB Read"; Expression={[math]::Round(($_.totalBytesReadFromSource)/(1024*1024*1024))}},
                                            @{Name="GB Written"; Expression={[math]::Round(($_.totalPhysicalBackupSizeBytes)/(1024*1024*1024))}} | ft 
        
        }
        
        if ($unit -eq "TB") {
            $run | Select-Object -Property @{Name="Run Date"; Expression={usecsToDate $_.startTimeUsecs}},
                                            @{Name="Source Size"; Expression={[math]::Round(($_.totalSourceSizeBytes)/(1024*1024*1024*1024))}},
                                            @{Name="Run Seconds"; Expression={[math]::Round(($_.endTimeUsecs - $_.startTimeUsecs)/(1000*1000))}},
                                            @{Name="TB Read"; Expression={[math]::Round(($_.totalBytesReadFromSource)/(1024*1024*1024*1024))}},
                                            @{Name="TB Written"; Expression={[math]::Round(($_.totalPhysicalBackupSizeBytes)/(1024*1024*1024*1024))}} | ft 
        
        }
                    
        $fsum = 0
        $bsum = 0
        $tsum = 0
        $asum = 0

        $iceboxArchiveBytes | Foreach { $asum += $_}
            
        $sum = $run.totalBytesReadFromSource
        $sum | Foreach { $fsum += $_}
            
        $sum = $run.totalPhysicalBackupSizeBytes
        $sum | Foreach { $bsum += $_}

        $tsum = $run.totalSourceSizeBytes[0]

        if ($fsum -eq $tsum) 
        { 
            $backupsize = $fsum
        } else {
            $backupsize = $tsum + $fsum 
        }

        if ($unit -eq "MB") {
            $bunitsum = [math]::Round($bsum/(1024*1024))
            $funitsum = [math]::Round($fsum/(1024*1024))
            $totalsum = [math]::Round($tsum/(1024*1024))
            $backupsize = [math]::Round($backupsize/(1024*1024))
            $archivedCapacity = [math]::Round($asum/(1024*1024))
        }
        
        if ($unit -eq "GB") {
            $bunitsum = [math]::Round($bsum/(1024*1024*1024))
            $funitsum = [math]::Round($fsum/(1024*1024*1024))
            $totalsum = [math]::Round($tsum/(1024*1024*1024))
            $backupsize = [math]::Round($backupsize/(1024*1024*1024))
            $archivedCapacity = [math]::Round($asum/(1024*1024*1024))
        }
        
        if ($unit -eq "TB") {
            $bunitsum = [math]::Round($bsum/(1024*1024*1024*1024))
            $funitsum = [math]::Round($fsum/(1024*1024*1024*1024))
            $totalsum = [math]::Round($tsum/(1024*1024*1024*1024))
            $backupsize = [math]::Round($backupsize/(1024*1024*1024*1024))
            $archivedCapacity = [math]::Round($asum/(1024*1024*1024*1024))
        }
        
        write-host "Total backupsize: $backupsize $unit"
        write-host "Total frontend capacity: $funitsum $unit"
        write-host "Total backend capacity used: $bunitsum $unit"
        write-host "Total CloudArchive capacity used: $archivedCapacity $unit"
        
        if ($export) {
            $line = "'{0}','{1}','{2}','{3}','{4}','{5}','{6}','{7}','{8}'" -f $jobName, $totalsum, $backupsize, $funitsum, $bunitsum, $archivedCapacity, $tenantName, $tenantId, $remoteClusterName
            Add-Content -Path $export -Value $line
        } 
    } else {
        $rundate = usecsToDate $startDate
        write-host "No jobruns for $jobName since $runDate"  -ForegroundColor Yellow
    }   
} 
