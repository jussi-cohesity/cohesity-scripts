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
Add-Content -Path $export -Value "Nodename`t;`tReporting GB"

$report = @{}

$jobs = api get "data-protect/protection-groups?isDeleted=false&includeTenants=true&includeLastRunInfo=true&environments=kSQL,kVMware,kPhysical,kOracle" -v2

foreach ($job in $jobs.protectionGroups) {
  $jobName = $job.name
  $jobId = $job.id.split(':')[2]
  Write-Host "Collecting stats for Protection Group $($job.name)" -ForegroundColor Yellow
    $runs = api get protectionRuns?jobId=$($jobId)`&excludeNonRestoreableRuns=false
    foreach ($run in $runs) {
        if ($run.backupRun.snapshotsDeleted -eq $false) {
            foreach($source in $run.backupRun.sourceBackupStatus) {
                $sourcename = $source.source.name
                if($sourcename -notin $report.Keys){
                    $report[$sourcename] = @{}
                    $report[$sourcename]['protectionGroup'] = $jobName
                    $report[$sourcename]['size'] = 0
                }
                $report[$sourcename]['size'] += $source.stats.totalBytesReadFromSource
            }
        }
    }       
}

### Export data
Write-Host "Exporting data..." -ForegroundColor Yellow
$report.GetEnumerator() | Sort-Object -Property {$_.Name} | ForEach-Object {
    $totalSize =  [math]::Round($_.Value.size/1GB,2)
    $line = "{0}`t;`t{1}" -f $_.Name, $totalSize
    Add-Content -Path $export -Value $line   
}
