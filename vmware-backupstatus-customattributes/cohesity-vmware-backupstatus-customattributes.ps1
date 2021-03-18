[CmdletBinding()]
param (
    [Parameter(Mandatory = $True)][string]$cohesityCluster, #the cluster to connect to (DNS name or IP)
    [Parameter(Mandatory = $True)][string]$cohesityCred, #credentials file for cohesity
    [Parameter(Mandatory = $True)][string]$vmwareCred #credentials file for cohesity
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

### Search VMware objects protected

Write-Host "Getting VMware Object protection statusinfo"

$report = @{}

$protectionSourceObjects = Get-CohesityProtectionSourceObject KVMware
$sources = $protectionSourceObjects | Where-Object { $_.vmWareProtectionSource.type -eq 'kVirtualMachine' }

foreach ($source in $sources) {
    $lastrun = Get-CohesityProtectionJobrun -Sourceid ($source.id) -numruns 1
    if ($lastrun) {
        $sourceName = $source.name
        Write-Host "Getting details for $sourceName"

        $lastRunStatus = $lastrun.backupRun.status
        $lastRunStartUsecs = Convert-CohesityUsecsToDateTime -usecs ($lastrun.backupRun.stats.startTimeUsecs)
        $lastRunTimeStamp = $lastRunStartUsecs.dateTime
        $sourceParent = $protectionSourceObjects | Where-Object { $_.id -eq $source.parentId }

        
        if($sourceName -notin $report.Keus) {
            $report[$sourcename] = @{}
            $report[$sourcename]['lastRunStatus'] = $lastRunStatus
            $report[$sourcename]['lastRunTimeStamp'] = $lastRunTimeStamp
            $report[$sourcename]['lastRunJobName'] = $lastrun.jobName
            $report[$sourcename]['vCenter'] = $sourceParent.name

        }
    }
}

## Change attributes

$report.GetEnumerator() | Sort-Object -Property {$_.Value.vCenter} | ForEach-Object {
    $vm = $_.Name
    
    if ($_.Value.vCenter -eq $connectedVcenter) {

        $notes = "`r`n"+"Last Backup Status: $($_.Value.lastRunStatus)"+"`r`n"+"Last Backup TimeStamp: $($_.Value.lastRunTimeStamp)"+"`r`n"+"Last Backup Protection Group: $($_.Value.lastRunJobName)"
        Set-VM $VM -Notes $notes

    } else {
        ### Connect to VMware vCenter
        $vmwareCredential = Import-Clixml -Path ($vmwareCred)
        try {
            Connect-VIServer -Server $($_.Value.vCenter) -Credential $vmwareCredential
            Write-Host "Connected to VMware vCenter $($global:DefaultVIServer.Name)" -ForegroundColor Yellow
            $connectedVcenter = $($global:DefaultVIServer.Name)
        } catch {
            write-host "Cannot connect to VMware vCenter $($_.Value.vCenter)" -ForegroundColor Yellow
            exit
        }
    }
  
}
