[CmdletBinding()]
param (
    [Parameter(Mandatory = $True)][string]$cohesityCluster, #the cluster to connect to (DNS name or IP)
    [Parameter(Mandatory = $True)][string]$cohesityCred, #credentials file for cohesity
    [Parameter(Mandatory = $True)][string]$export 
)

Write-Host "Importing credentials from credential file $($cohesityCred)" -ForegroundColor Yellow
Write-Host "Connecting to Cohesity Cluster $($cohesityCluster)" -ForegroundColor Yellow

$Credential = Import-Clixml -Path ($cohesityCred)
try {
    Connect-CohesityCluster -Server $cohesityCluster -Credential $Credential
    Write-Host "Connected to Cohesity Cluster $($cohesityCluster)" -ForegroundColor Yellow
} catch {
    write-host "Cannot connect to Cohesity cluster $($cohesityCluster)" -ForegroundColor Yellow
    exit
}

### Add headers to export-file
Add-Content -Path $export -Value "vCenter Name, Protection Group, VM Name, Last Run Status, Last Run TimeStamp"


### Search VMware objects protected

Write-Host "Getting VMware Object protection statusinfo"

$report = @{}

$protectionSourceObjects = Get-CohesityProtectionSourceObject KVMware
$sources = $protectionSourceObjects | Where-Object { $_.vmWareProtectionSource.type -eq 'kVirtualMachine' -and $_.vmWareProtectionSource.hostType -eq 'kLinux' }

foreach ($source in $sources) {
    $lastrun = Get-CohesityProtectionJobrun -Sourceid ($source.id) -numruns 1
    if ($lastrun) {
        $sourceName = $source.name
        Write-Host "Getting details for $sourceName"

        $lastRunStatus = $lastrun.backupRun.status
        $lastRunStartUsecs = Convert-CohesityUsecsToDateTime -usecs ($lastrun.backupRun.stats.startTimeUsecs)
        $lastRunTimeStamp = $lastRunStartUsecs.dateTime
        $sourceParent = $protectionSourceObjects | Where-Object { $_.id -eq $source.parentId }

        
        if($sourceName -notin $report.Keus) {
            $report[$sourcename] = @{}
            $report[$sourcename]['lastRunStatus'] = $lastRunStatus
            $report[$sourcename]['lastRunTimeStamp'] = $lastRunTimeStamp
            $report[$sourcename]['lastRunJobName'] = $lastrun.jobName
            $report[$sourcename]['vCenter'] = $sourceParent.name

        }
    }
}

## Export content
$report.GetEnumerator() | Sort-Object -Property {$_.Value.vCenter} | ForEach-Object {
    $vm = $_.Name
    
    $line = "{0},{1},{2},{3},{4}" -f $_.Value.vCenter, $_.Value.lastRunJobName, $vm, $_.Value.lastRunStatus, $_.Value.lastRunTimeStamp
    Add-Content -Path $export -Value $line
}
