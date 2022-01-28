### usage: ./cohesity-object-stats.ps1 -vip cohesity01 -username admin [ -domain local ] 

### Sample script to report object frontend capacity - Jussi Jaurola <jussi@cohesity.com>


### process commandline arguments
[CmdletBinding()]
param (
    [Parameter(Mandatory = $True)][string]$vip, 
    [Parameter(Mandatory = $True)][string]$username,
    [Parameter()][string]$domain = 'local'
    )

### source the cohesity-api helper code 
. ./cohesity-api.ps1

try {
    apiauth -vip $vip -username $username -domain $domain
    $clusterName = (api get cluster).name
} catch {
    write-host "Cannot connect to cluster $vip" -ForegroundColor Yellow
    exit
}

### Get mSec time for days 
$date = [DateTime]::Today.AddHours(23).AddMinutes(59).AddSeconds(59)
$endTimeMsecs = [DateTimeOffset]::new($date).ToUnixTimeMilliSeconds()
$today = Get-Date -Format "dd.MM.yyyy"

### Add headers to export-file
$export = "cohesity_" + $today + ".csv"
$line = "PVM`t;`t{0}" -f $today
Add-Content -Path $export -Value $line
Add-Content -Path $export -Value "Nodename`t;`tProtection Group;`tSource Size GB;`tGB Read;`tLocal GB Written;`tCloud GB Written"

$report = @{}

$jobs = api get "data-protect/protection-groups?isDeleted=false&includeTenants=true&includeLastRunInfo=true&environments=kSQL,kVMware,kPhysical,kOracle" -v2

foreach ($job in $jobs.protectionGroups) {
  $jobName = $job.name
  $jobId = $job.id.split(':')[2]
  Write-Host "Collecting stats for Protection Group $($job.name)" -ForegroundColor Yellow
    $runs = api get protectionRuns?jobId=$($jobId)`&excludeNonRestoreableRuns=false
    foreach ($run in $runs) {
        if ($run.copyRun.status[0]) { $cloudArchiveInUse = $true } else { $cloudArchiveInUse = $false }
        if ($run.backupRun.snapshotsDeleted -eq $false) {
            foreach($source in $run.backupRun.sourceBackupStatus) {
                $sourcename = $source.source.name
                if($sourcename -notin $report.Keys){
                    $report[$sourcename] = @{}
                    $report[$sourcename]['protectionGroup'] = $jobName
                    $report[$sourcename]['totalSourceSizeBytes'] = 0
                    $report[$sourcename]['totalBytesReadFromSource'] = 0
                    $report[$sourcename]['totalPhysicalBackupSizeBytes'] = 0
                    $report[$sourcename]['totalCloudBackupSizeBytes'] = 0
                }
                $report[$sourcename]['totalSourceSizeBytes'] = [math]::Round($source.stats.totalSourceSizeBytes/1GB,2)
                $report[$sourcename]['totalBytesReadFromSource'] += [math]::Round($source.stats.totalBytesReadFromSource/1GB,2)
                $report[$sourcename]['totalPhysicalBackupSizeBytes'] += [math]::Round($source.stats.totalPhysicalBackupSizeBytes/1GB,2)  
                
                if ($cloudArchiveInUse -eq $true) {
                    $report[$sourcename]['totalCloudBackupSizeBytes'] += [math]::Round($source.stats.totalPhysicalBackupSizeBytes/1GB,2)
                }
            }
        }
    }       
}

### Export data
Write-Host "Exporting data..." -ForegroundColor Yellow
$report.GetEnumerator() | Sort-Object -Property {$_.Name} | ForEach-Object {
    $line = "{0}`t;`t{1};`t{2};`t{3};`t{4};`t{5}" -f $_.Name, $_.Value.protectionGroup, $_.Value.totalSourceSizeBytes, $_.Value.totalBytesReadFromSource, $_.Value.totalPhysicalBackupSizeBytes, $_.Value.totalCloudBackupSizeBytes
    Add-Content -Path $export -Value $line   
}
