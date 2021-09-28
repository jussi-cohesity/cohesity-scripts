[CmdletBinding()]
param (
    [Parameter(Mandatory = $True)][string]$cohesityCluster, #the cluster to connect to (DNS name or IP)
    [Parameter(Mandatory = $True)][string]$cohesityCred, #credentials file for cohesity
    [Parameter(Mandatory = $True)][string]$serverCred, #credentials file for server
    [Parameter(Mandatory = $True)][string]$filename, #full path for file to recover
    [Parameter(Mandatory = $True)][string]$newdir, #full path for directory to recover file
    [Parameter(Mandatory = $True)][string]$server #source server for file to recover
)

Write-Host "Importing credentials from credential file $($cohesityCred)" -ForegroundColor Yellow
Write-Host "Connecting to Cohesity Cluster $($cohesityCluster)" -ForegroundColor Yellow

$Credential = Import-Clixml -Path ($cohesityCred)
$TargetHostCredentials = Import-Clixml -Path ($serverCred)

try {
    Connect-CohesityCluster -Server $cohesityCluster -Credential $Credential
    Write-Host "Connected to Cohesity Cluster $($cohesityCluster)" -ForegroundColor Yellow
} catch {
    write-host "Cannot connect to Cohesity cluster $($cohesityCluster)" -ForegroundColor Red
    exit
}

# Find protection group for file and server

$protectionSource = Find-CohesityObjectsForRestore -Search $server -Environments kVMware | Where { $_.ObjectName -eq $server } | Select-Object -First 1
if (!$protectionSource) {
    Write-Host "Cannot find protection source for server $server" -ForegroundColor Red
    exit
}
$today = Get-Date -Format "yyyyMMdd"
$taskName = "RecoveryTest_" + $server + "_" + $today
$protectionSourceId = $protectionSource.SnapshottedSource.Id
$protectionSourceJobId = $protectionSource.JobId
$protectionSourceHostType = $protectionSource.SnapshottedSource.VmWareProtectionSource.HostType
$protectionSourceParentId = $protectionSource.RegisteredSource.id

# Recover file
$restoreTask = Restore-CohesityFile -TaskName $taskName -FileNames $filename -JobId $protectionSourceJobId -SourceId $protectionSourceId -TargetSourceId $protectionSourceId -TargetParentSourceId $protectionSourceParentId -TargetHostTYpe $protectionSourceHostType -TargetHostCredential $TargetHostCredentials
Write-Host "Running recovery test for file $filename to server $server" -ForegroundColor Yellow

# Wait 1 minute
Start-Sleep 15
$sleepCount = 0

While ($true) {
    $validateTask = (Get-CohesityRestoreTask -Id restoreTask.Id).Status
    Write-Host "Current status for recovery job is $validateTask"

    if ($validateTask -eq 'kFinished') {
        break
    } elseif ($sleepCount -gt '10') {
        Write-Host "Restore takes too long. Failing tests!" -ForegroundColor Red
        exit
    } else {
        Start-Sleep 30
        $sleepCount++
    }
}
