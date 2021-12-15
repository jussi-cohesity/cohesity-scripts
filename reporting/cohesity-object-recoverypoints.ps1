### Sample script to report object snapshots and their expiry times - Jussi Jaurola <jussi@cohesity.com>

### process commandline arguments
[CmdletBinding()]
param (
    [Parameter(Mandatory = $True)][string]$cluster, 
    [Parameter(Mandatory = $True)][string]$apikey,
    [Parameter()][string]$protectionGroup,
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
    "Object, Protection Group, Local Copy Start Time, Local Copy Expire Time, Archive Target, Archive Copy Start Time, Archive Copy Expire Time" | Out-File -FilePath $export
}
$report = @()
$protectionGroups = [System.Collections.ArrayList]::new()
### Objets to look
$environments = "kVMware", "kPhysical"

Write-Host "Getting all objects for environments $environments" -ForegroundColor Yellow

$objects = Find-CohesityObjectsForRestore -Environments $environments
if ($protectionGroup) {
    $protectiongroups.Add($protectionGroup) | out-null
} else {
    $jobs = Get-CohesityProtectionJob -Environments $environments | Select-Object Name
    
    foreach ($job in $jobs) {
        $protectionGroups.Add($job.name) | out-null
    }
}

foreach ($protectiongroup in $protectiongroups) {
    Write-Host "Collecting stats for Protection Group $protectionGroup" -ForegroundColor Yellow
    $allruns = Get-CohesityProtectionJobRun -JobName $protectionGroup -ExcludeNonRestoreableRuns
    
    if (!$allruns) {
        Write-Host "Cannot find any runs for Protection Group $protectionGroup. Please check!" -ForegroundColor Red
        exit
    }
    
    Write-Host "    Collecting stats for objects" -ForegroundColor Yellow
    foreach ($object in $objects) {
        $objectName = $object.ObjectName
        $objectId = $object.SnapshottedSource.Id
        Write-Host "        Collecting available snapshots for $objectName" -ForegroundColor Yellow

        $runs = $allruns | Where { $_.backupRun.sourceBackupStatus.source.name -eq $objectName } | Where { $_.backupRun.snapshotsdeleted -eq $false }

        foreach ($run in $runs) {

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

            $report = @($report + ("{0},{1},{2},{3},{4},{5},{6}" -f $objectName, $protectiongroup, $localStartTime, $localExpiryTime, $archiveTargetName, $archiveStartTime, $archiveExpiryTime))
        }
    }
    
}

if ($export) {
    Write-Host "Exporting data to $export" -ForegroundColor Yellow
    $report | Sort-Object | Out-File -FilePath $export -Append
} else {
    $report | Sort-Object
}
