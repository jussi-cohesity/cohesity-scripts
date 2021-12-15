### Sample script report objects all recovery points and expiry times - Jussi Jaurola <jussi@cohesity.com>


### process commandline arguments
[CmdletBinding()]
param (
    [Parameter(Mandatory = $True)][string]$cluster, 
    [Parameter(Mandatory = $True)][string]$apikey,
    [Parameter(Mandatory = $True)][string]$export 
    )

if (!(Get-Module -ListAvailable -Name Cohesity.PowerShell.Core)) {
    Write-Host "Please install Cohesity.PowerShell.Core -powershell module before running this script!" -ForegroundColor Red
    exit
}

try {
    Connect-CohesityCluster -Server $cluster -APIKey $apikey
} catch {
    write-host "Cannot connect to cluster $cluster" -ForegroundColor Yellow
    exit
}

if ($export) {
    "`nObject, Protection Group, Local Copy Start Time, Local Copy Expire Time, Archive Target, Archive Copy Start Time, Archive Copy Expire Time" | Out-File -FilePath $export
}
$report = @()

### Objets to look
$environments = "kVMware", "kPhysical"

Write-Host "Getting all objects for environments $environments" -ForegroundColor Yellow

$objects = Find-CohesityObjectsForRestore -Environments $environments 

Write-Host "Collecting stats for objects" -ForegroundColor Yellow
foreach ($object in $objects) {
    $objectName = $object.ObjectName
    $objectId = $object.SnapshottedSource.Id
    Write-Host "    Collecting available snapshots for $objectName" -ForegroundColor Yellow

    $runs = Get-CohesityProtectionJobRun -SourceId $objectId -ExcludeErrorRuns -ExcludeNonRestoreableRuns

    foreach ($run in $runs) {
        $jobName = $run.jobName

        foreach ($copyRun in $run.copyRun) {
            if ($copyRun.target.type -eq 'kLocal') {
                $localStartTime = Convert-CohesityUsecsToDateTime -Usecs $copyRun.runStartTimeUsecs
                $localExpiryTime = Convert-CohesityUsecsToDateTime -Usecs $copyRun.expiryTimeUsecs
            }

            if ($copyRun.target.type -eq 'kArchival') {
                $archiveTargetName = $copyRun.target.archivalTarget.vaultName
                $archiveStartTime = Convert-CohesityUsecsToDateTime -Usecs $copyRun.runStartTimeUsecs
                $archiveExpiryTime = Convert-CohesityUsecsToDateTime -Usecs $copyRun.expiryTimeUsecs
            }
        }

        $report = @($report + ("{0},{1},{2},{3},{4},{5},{6}" -f $objectName, $jobName, $localStartTime, $localExpiryTime, $archiveTargetName, $archiveStartTime, $archiveExpiryTime))
    }
}

$report | Sort-Object

if ($export) {
    Write-Host "Exporting data to $export" -ForegroundColor Yellow
    $report | Sort-Object | Out-File -FilePath $export -Append
}
