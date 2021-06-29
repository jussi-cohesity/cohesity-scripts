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


$report = @{}

### Search VMware objects protected
$protectionSourceObjects = Get-CohesityProtectionSourceObject KVMware
Write-Host "Getting VMware Protection Groups..."

$jobs = Get-CohesityProtectionJob -Environments KVMware | Select-Object Id,Name

foreach ($job in $jobs) {
    Write-Host "Collecting all objects for Protection Group $($job.name)"
    $lastrun = Get-CohesityProtectionJobRun -JobId $($job.id) -ExcludeNonRestoreableRuns -NumRuns 1
    if ($lastrun) {
        foreach ($source in $lastrun.backupRun.sourceBackupStatus) {
            $sourceName = $source.source.name
            Write-Host "   Getting details for object $sourceName"
            $lastRunStatus = $source.status
            $lastRunTimeStamp = Convert-CohesityUsecsToDateTime -Usecs $source.stats.startTimeUsecs
            $sourceParent = $protectionSourceObjects | Where-Object { $_.id -eq $source.source.parentId }
            
            if($sourceName -notin $report.Keys) {
                $report[$sourcename] = @{}
                $report[$sourcename]['lastRunStatus'] = $lastRunStatus
                $report[$sourcename]['lastRunTimeStamp'] = $lastRunTimeStamp
                $report[$sourcename]['lastRunJobName'] = $job.name
                $report[$sourcename]['vCenter'] = $sourceParent.name
            }
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

        if (!$lastRunStatusAttribute) { New-CustomAttribute -Name "Cohesity Last Backup Status" -TargetType VirtualMachine }
        if (!$lastBackupTimeStampAttribute) { New-CustomAttribute -Name "Cohesity Last Backup TimeStamp" -TargetType VirtualMachine }
        if (!$lastRunJobNameAttribute) { New-CustomAttribute -Name "Cohesity Last Backup ProtectionGroup" -TargetType VirtualMachine }
        

        ### Set notes
        Write-Host "Updating $vm notes field"
        Set-Annotation -Entity $vm -CustomAttribute "Cohesity Last Backup Status" -Value $($_.Value.lastRunStatus)
        Set-Annotation -Entity $vm -CustomAttribute "Cohesity Last Backup TimeStamp" -Value $($_.Value.lastRunTimeStamp)
        Set-Annotation -Entity $vm -CustomAttribute "Cohesity Last Backup ProtectionGroup" -Value $($_.Value.lastRunJobName)
        
    }
}
