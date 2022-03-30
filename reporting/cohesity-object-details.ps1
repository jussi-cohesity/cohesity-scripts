### usage: ./cohesity-object-details.ps1 -vip cohesity01 -username admin [ -domain local ] 

### Sample script to report object capacity details - Jussi Jaurola <jussi@cohesity.com>


### process commandline arguments
[CmdletBinding()]
param (
    [Parameter(Mandatory = $True)][string]$vip, 
    [Parameter(Mandatory = $True)][string]$username,
    [Parameter()][string]$domain = 'local',
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

$today = Get-Date -Format "dd.MM.yyyy"

### Add headers to export-file
$export = "cohesity_" + $today + ".csv"

Add-Content -Path $export -Value "Source Name, Protection Group, Source Size, Source Type, Source OS, Data In (bytes), Data Written (bytes)"
$report = @{}

Write-Host "Collecting all source objects" -ForegroundColor Yellow
$objects = api get protectionSources/objects | Where { $_.environment -eq 'kVMware' -or $_.environment -eq 'kSQL' -or $_.environment -eq 'kPhysical'}


foreach ($object in $objects) {
    $objectName = $object.name
    Write-Host "    Collecting source details for $objectName" -ForegroundColor Yellow
    $objectSourceType = $object.environment

    ### Details for VMware objects
    if ($objectSourceType -eq 'kVMware') { 
        $objectSourceOS = $object.vmWareProtectionSource.hostType
        $objectSourceSize = 0
        foreach ($virtualDisk in $object.vmWareProtectionSource.virtualDisks) {
            $objectSourceSize += $virtualDisk.logicalSizeBytes
        }
    }

    ### Details for Physical servers
    if ($objectSourceType -eq 'kPhysical') {
        $objectSourceOS = $object.physicalProtectionSource.hostType
        $objectSourceSize = 0
        foreach ($volume in $object.physicalProtectionSource.volumes) {
            $objectSourceSize += $volume.usedSizeBytes
        }
    }

    ### Details for SQL servers
    if ($objectSourceType -eq 'kSQL') {
        $objectSourceOS = "MSSQL"       
        $objectSourceSize = 0
        foreach ($file in $object.sqlProtectionSource.dbFiles) {
            $objectSourceSize += $file.sizeBytes
        }
    }

    if($objectName -notin $report.Keys){
        $report[$objectName] = @{}
        $report[$objectName]['sourceId'] = $object.id
        $report[$objectName]['sourceSize'] = $objectSourceSize
        $report[$objectName]['sourceType'] = $objectSourceType
        $report[$objectName]['sourceOS'] = $objectSourceOS
        $report[$objectName]['protectionGroup'] = 0
        $report[$objectName]['sourceDataIn'] = 0
        $report[$objectName]['sourceDataWritten'] = 0
    }
}

Write-Host "Getting Protection Groups" -ForegroundColor Yellow
$jobs = api get "data-protect/protection-groups?isDeleted=false&includeTenants=true&includeLastRunInfo=true&environments=kSQL,kVMware,kPhysical,kOracle" -v2

foreach ($job in $jobs.protectionGroups) {
    $jobName = $job.name
    $jobId = $job.id.split(':')[2]
    Write-Host "    Collecting stats for Protection Group $($job.name)" -ForegroundColor Yellow
    $runs = api get protectionRuns?jobId=$($jobId)`&excludeNonRestoreableRuns=false
    foreach ($run in $runs) {        
        foreach($source in $run.backupRun.sourceBackupStatus) {
            $sourcename = $source.source.name
            if($sourcename -in $report.Keys) {
                $report[$sourcename]['protectionGroup'] = $jobName
                $report[$sourcename]['sourceDataIn'] += $source.stats.totalBytesReadFromSource
                $report[$sourcename]['sourceDataWritten'] += $source.stats.totalPhysicalBackupSizeBytes
            }
        }
    }       
}

Write-Host "Exporting data" -ForegroundColor Yellow
$report.GetEnumerator() | Sort-Object -Property {$_.Name} | ForEach-Object {
    $line = "{0},{1},{2},{3},{4},{5},{6}" -f $_.Name, $_.Value.protectionGroup, $_.Value.sourceSize, $_.Value.sourceType, $_.Value.sourceOS, $_.Value.sourceDataIn, $_.Value.sourceDataWritten
    Add-Content -Path $export -Value $line
}
