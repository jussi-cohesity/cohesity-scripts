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

        ### Set notes
        Write-Host "Updating $vm notes field"
        Set-Annotation -Entity $vm -CustomAttribute "Cohesity Last Backup Status" -Value $($_.Value.lastRunStatus)
        Set-Annotation -Entity $vm -CustomAttribute "Cohesity Last Backup TimeStamp" -Value $($_.Value.lastRunTimeStamp)
        Set-Annotation -Entity $vm -CustomAttribute "Cohesity Last Backup ProtectionGroup" -Value $($_.Value.lastRunJobName)

    } else {
        ### Connect to VMware vCenter
        $vmwareCredential = Import-Clixml -Path ($vmwareCred)
        try {
            Connect-VIServer -Server $($_.Value.vCenter) -Credential $vmwareCredential
            Write-Host "Connected to VMware vCenter $($global:DefaultVIServer.Name)" -ForegroundColor Yellow
            $connectedVcenter = $_.Value.vCenter
        } catch {
            write-host "Cannot connect to VMware vCenter $($_.Value.vCenter)" -ForegroundColor Yellow
            exit
        }

        ## Check if Custom Attributes are created, if not add them
        $lastRunStatusAttribute = (Get-CustomAttribute | Where-Object {$_.Name -eq "Cohesity Last Backup Status"}).Key
        $lastBackupTimeStampAttribute = (Get-CustomAttribute | Where-Object {$_.Name -eq "Cohesity Last Backup TimeStamp"}).Key
        $lastRunJobNameAttribute = (Get-CustomAttribute | Where-Object {$_.Name -eq "Cohesity Last Backup ProtectionGroup"}).Key

        if (!$lastRunStatusAttribute) { New-CustomAttribute -Name "Cohesity Last Backup Status" -TargetName VirtualMachine }
        if (!$lastBackupTimeStampAttribute) { New-CustomAttribute -Name "Cohesity Last Backup TimeStamp" -TargetName VirtualMachine }
        if (!$lastRunJobNameAttribute) { New-CustomAttribute -Name "Cohesity Last Backup ProtectionGroup" -TargetName VirtualMachine }
        

        ### Set notes
        Write-Host "Updating $vm notes field"
        Set-Annotation -Entity $vm -CustomAttribute "Cohesity Last Backup Status" -Value $($_.Value.lastRunStatus)
        Set-Annotation -Entity $vm -CustomAttribute "Cohesity Last Backup TimeStamp" -Value $($_.Value.lastRunTimeStamp)
        Set-Annotation -Entity $vm -CustomAttribute "Cohesity Last Backup ProtectionGroup" -Value $($_.Value.lastRunJobName)
        
    }
}
