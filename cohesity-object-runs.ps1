### Example script to list all protection run details for object - Jussi Jaurola <jussi@cohesity.com>

### Note! You need to have cohesity-api.ps1 on same directory!


### process commandline arguments
[CmdletBinding()]
param (
    [Parameter(Mandatory = $True)][string]$cluster, 
    [Parameter(Mandatory = $True)][string]$username,
    [Parameter()][string]$domain = 'local',
    [Parameter()][ValidateSet('MB','GB','TB')][string]$unit = "GB",
    [Parameter()][string]$startDate = (Get-Date).AddMonths(-1),
    [Parameter()][string]$endDate = (get-date)
    [Parameter(Mandatory = $true)][string]$object
    )

### source the cohesity-api helper code 
. $(Join-Path -Path $PSScriptRoot -ChildPath cohesity-api.ps1)

try {
    apiauth -vip $cluster -username $username -domain $domain
    $clusterName = (api get cluster).name
} catch {
    write-host "Cannot connect to cluster $cluster" -ForegroundColor Yellow
    exit
}
### Get usage stats
$units = "1" + $unit

"Searching protection runs for object $object. Hang on. This might take long!"

$jobs = (api get "data-protect/search/objects?searchString=$($object)&includeTenants=true" -v2).objects.objectProtectionInfos.protectionGroups

foreach ($job in $jobs) {
    $jobId = $job.id.split(':')[2]
    $runs = ((api get "protectionRuns?jobId=$($jobId)&excludeNonRestoreableRuns=true&startTimeUsecs=$(dateToUsecs $startDate)&endTimeUsecs=$(dateToUsecs $endDate)").backupRun.sourceBackupStatus | Where { $_.source.name -eq $object}).stats
    if ($runs) {
        "`n$($clusterName): $global:object ($($job.name))`n"
        "Start Time          End Time            Read ($unit)    Logical Size ($unit)"
        "------------------  ------------------  ---------    -----------------"   
        foreach ($run in $runs) {
            $runStart = $run.startTimeUsecs
            $runEnd = $run.endTimeUsecs
            $objectRunStart = (usecsToDate $runStart).ToString("MM/dd/yyyy hh:mmtt")
            $objectRunEnd = (usecsToDate $runEnd).ToString("MM/dd/yyyy hh:mmtt")
            $objectRead = [math]::Round($run.totalBytesReadFromSource/$units,2)
            $objectLogicalSize = [math]::Round($run.totalLogicalBackupSizeBytes/$units,2)
            "{0,-19} {1,-19} {2,-12} {3,-2}" -f $objectRunStart, $objectRunEnd, $objectRead, $objectLogicalSize
        }
    }
}
