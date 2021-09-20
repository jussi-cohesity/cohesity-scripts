### usage: ./cohesity-object-stats.ps1 -vip 192.168.1.198 -username admin [ -domain local ] [-export 'filename.csv']

### Sample script to report object frontend capacity - Jussi Jaurola <jussi@cohesity.com>


### process commandline arguments
[CmdletBinding()]
param (
    [Parameter(Mandatory = $True)][string]$vip, 
    [Parameter(Mandatory = $True)][string]$username,
    [Parameter()][string]$domain = 'local',
    [Parameter(Mandatory = $True)][string]$export 
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

### Add headers to export-file
Add-Content -Path $export -Value "Object, ProtectionGroup, Data Read (bytes)"


$report = @{}

### Get mSec time for days 
$date = [DateTime]::Today.AddHours(23).AddMinutes(59).AddSeconds(59)
$endTimeMsecs = [DateTimeOffset]::new($date).ToUnixTimeMilliSeconds()


$jobs = api get "data-protect/protection-groups?isDeleted=false&includeTenants=true&includeLastRunInfo=true&environments=kSQL,kVMware,kPhysical,kOracle" -v2

foreach ($job in $jobs.protectionGroups) {
  $jobName = $job.name
  $jobId = $job.id.split(':')[2]
  Write-Host "Collecting stats for Protection Group $($job.name)" -ForegroundColor Yellow
            $runs = api get protectionRuns?jobId=$($jobId)`&excludeNonRestoreableRuns=true
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
}

### Export data


$report.GetEnumerator() | Sort-Object -Property {$_.Name} | ForEach-Object {

    $line = "{0},{1},{2}" -f $_.Name, $_.Value.protectionGroup, $_.Value.size
    Add-Content -Path $export -Value $line   
}
