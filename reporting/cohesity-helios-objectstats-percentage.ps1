### Example script to calculate object usage share out of protectiongroup used from helios - Jussi Jaurola <jussi@cohesity.com>

### Note! You need to have cohesity-api.ps1 on same directory!


### process commandline arguments
[CmdletBinding()]
param (
    [Parameter(Mandatory = $True)][string]$apikey,
    [Parameter()][ValidateSet('MB','GB','TB')][string]$unit = "GB",
    [Parameter()][switch]$lastMonthOnly,
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

$startTimeUsecs = dateToUsecs (Get-Date -Day 1).Date.AddMonths(-1)
$endTimeUsecs =  dateToUsecs  (Get-Date -Day 1).Date.AddMonths(-1).AddMilliseconds(-1).Date.AddMonths(1)

### Add headers to export-file
Add-Content -Path $export -Value "Customer, Protection Group, Source, Source Size ($unit)"

### Get usage stats
$units = "1" + $unit

$clusters = heliosClusters | Select-Object -Property name
$report = @{}
$jobStats = @{}

foreach ($cluster in $clusters.name) {
    ## Conenct to cluster
    Write-Host "Connecting cluster $cluster" -ForegroundColor Yellow
    heliosCluster $cluster

    Write-Host "    Getting Storage Consumers stats" -ForegroundColor Yellow
    $stats = api get "stats/consumers?maxCount=1000&fetchViewBoxName=true&fetchTenantName=true&fetchProtectionEnvironment=true&consumerType=kProtectionRuns"
    Write-Host "    Getting Protection Groups" -ForegroundColor Yellow
    $jobs = api get "data-protect/protection-groups?isDeleted=false&includeTenants=true&includeLastRunInfo=true&environments=kSQL,kVMware,kPhysical,kOracle" -v2
    Write-Host "    Getting Protection Policies" -ForegroundColor Yellow
    $policies = api get protectionPolicies

    foreach ($job in $jobs.protectionGroups) {
        $jobTotalRead = 0
        $jobName = $job.name
        $jobId = $job.id.split(':')[2]
        $customerName = $job.name.split('_')[0]
        Write-Host "    Collecting stats for Protection Group $($job.name)" -ForegroundColor Yellow
          
          ### Check if only last month is requested
          if ($lastMonthOnly) {
            $runs = api get protectionRuns?jobId=$($jobId)`&excludeNonRestoreableRuns=false`&startTimeUsecs=$startTimeUsecs`&endTimeUsecs=$endTimeUsecs
          } else {
            $runs = api get protectionRuns?jobId=$($jobId)`&excludeNonRestoreableRuns=false
          }
          foreach ($run in $runs) {
              ### Check if run contains cloudArchive task
              $isCloudArchive = $run.copyRun | Where { $_.target.type -eq 'kArchival' }
              if ($isCloudArchive) { $cloudArchiveInUse = $true } else { $cloudArchiveInUse = $false }
              
              if ($run.backupRun.snapshotsDeleted -eq $false) {
                  foreach($source in $run.backupRun.sourceBackupStatus) {
                      $sourcename = $source.source.name
                      if($sourcename -notin $report.Keys){
                          $report[$sourcename] = @{}
                          $report[$sourcename]['protectionGroup'] = $jobName
                          $report[$sourcename]['customerName'] = $customerName
                          $report[$sourcename]['totalBytesReadFromSource'] = 0
                          $report[$sourcename]['totalCloudBackupSizeBytes'] = 0
                          $report[$sourcename]['totalReadFromJobTotalRead'] = 0
                          $report[$sourcename]['totalWrittenFromJobTotalWritten'] = 0
                      }
                      $report[$sourcename]['totalBytesReadFromSource'] += [math]::Round($source.stats.totalBytesReadFromSource/$units,2)
                      
                      if ($cloudArchiveInUse -eq $true) {
                          $report[$sourcename]['totalCloudBackupSizeBytes'] += [math]::Round($source.stats.totalPhysicalBackupSizeBytes/$units,2)
                      }
                      $jobTotalRead += [math]::Round($source.stats.totalBytesReadFromSource/$units,2)
                  }
              }
          }
          $jobStats[$jobName] = @{}
          $jobStats[$jobname]['jobTotalRead'] = [math]::Round(($stats.statsList | Where { $_.name -eq $jobName }).stats.dataInBytes/$units,2)
          $jobStats[$jobname]['jobTotalWritten'] = [math]::Round(($stats.statsList | Where { $_.name -eq $jobName }).stats.dataWrittenBytes/$units,2)
      }

      ### Calculate object part of total capacity
      $report.GetEnumerator() | Sort-Object -Property {$_.Name} | ForEach-Object {
        $objectJobName = $_.Value.protectionGroup
        $sourceSize = $_.Value.totalBytesReadFromSource
        $objectJobTotalRead = $jobStats[$objectJobName]['jobTotalRead']
        $objectJobTotalWritten = $jobStats[$objectJobName]['jobTotalWritten']

        $objectPercentage = $sourceSize/$objectJobTotalRead

        $report[$_.Name]['totalReadFromJobTotalRead'] = $objectJobTotalRead * $objectPercentage
        $report[$_.Name]['totalWrittenFromJobTotalWritten'] = $objectJobTotalWritten * $objectPercentage

      }
}

### Export data
Write-Host "Exporting to $export" -ForegroundColor Yellow
$report.GetEnumerator() | Sort-Object -Property {$_.Name} | ForEach-Object {
    $line = "{0};{1};{2};{3}" -f $_.Value.customerName, $_.Value.protectionGroup, $_.Name, [math]::Round($_.Value.totalWrittenFromJobTotalWritten,2)
    Add-Content -Path $export -Value $line
}
