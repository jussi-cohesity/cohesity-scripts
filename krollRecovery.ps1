### usage: ./krollRecovery.ps1 -vip 192.168.1.198 -username admin [ -domain local ] -sourceServer 'SQL2012' -targetServer 'SQLDEV01' [-online 'true'] [-targetUsername 'Administrator'] [-targetpw 'Passw0rd']

### Automate Kroll OnTrack recovery for SQL/Sharepoint - Jussi Jaurola <jussi@cohesity.com>
###
### Some of the code is from Brian Seltzer's scripts. Thanks!
###

[CmdletBinding()]
param (
    [Parameter(Mandatory = $True)][string]$vip, #the cluster to connect to (DNS name or IP)
    [Parameter(Mandatory = $True)][string]$username, #username (local or AD)
    [Parameter()][string]$domain = 'local', #local or AD domain
    [Parameter(Mandatory = $True)][string]$sourceServer, #source server that was backed up
    [Parameter()][string]$targetServer = $env:COMPUTERNAME, #target server to mount the volumes to, default this computer
    [Parameter()][ValidateSet('true','false')][string]$online = "false", #bring disks online, default false
    [Parameter()][string]$targetUsername = '', #credentials to ensure disks are online (optional, needed if online is yes)
    [Parameter()][string]$targetPw = '' #credentials to ensure disks are online (optional, eeded if online is yes)
)

$finishedStates =  @('kCanceled', 'kSuccess', 'kFailure') 

### source the cohesity-api helper code
. ./cohesity-api

# Connect to Cohesity cluster
try {
    apiauth -vip $vip -username $username -domain $domain
} catch {
    write-host "Cannot connect to Cohesity cluster $vip" -ForegroundColor Yellow
    exit
}

### search for the source server
$searchResults = api get "/searchvms?entityTypes=kVMware&entityTypes=kPhysical&entityTypes=kHyperV&entityTypes=kHyperVVSS&entityTypes=kAcropolis&entityTypes=kView&vmName=$sourceServer"

### narrow the results to the correct server from this cluster
$searchResults = $searchresults.vms | Where-Object { $_.vmDocument.objectName -ieq $sourceServer } | Select-Object -First 1

### list snapshots for VM
$snapshots = $searchResults.vmDocument.versions.snapshotTimestampUsecs

if(!$searchResults){
    write-host "Source Server $sourceServer Not Found" -foregroundcolor yellow
    exit
}

$physicalEntities = api get "/entitiesOfType?environmentTypes=kVMware&environmentTypes=kPhysical&physicalEntityTypes=kHost&vmwareEntityTypes=kVCenter"
$virtualEntities = api get "/entitiesOfType?environmentTypes=kVMware&environmentTypes=kPhysical&&physicalEntityTypes=kHost&vmwareEntityTypes=kVirtualMachine" #&vmwareEntityTypes=kVCenter
$sourceEntity = (($physicalEntities + $virtualEntities) | Where-Object { $_.displayName -ieq $sourceServer })[0]
$targetEntity = (($physicalEntities + $virtualEntities) | Where-Object { $_.displayName -ieq $targetServer })[0]

if(!$sourceEntity){
    Write-Host "Source Server $sourceServer Not Found" -ForegroundColor Yellow
    exit
}

if(!$targetEntity){
    Write-Host "Target Server $targetServer Not Found" -ForegroundColor Yellow
    exit
}

Write-Host "Available recovery points:" -ForegroundColor Yellow
Write-Host "--------------------------" -ForegroundColor Yellow

$snapshots | ForEach-object -Begin {$i=0} -Process {"Id $i - $(usecsToDate $_)";$i++}
$snapshotId = Read-Host 'Enter ID of selected recovery point'


if ($online -eq 'false') {
    $mountTask = @{
        'name' = 'Kroll OnTrack recovery mount';
        'objects' = @(
            @{
                'jobId' = $searchResults.vmDocument.objectId.jobId;
                'jobUid' = $searchResults.vmDocument.objectId.jobUid;
                'entity' = $sourceEntity;
                'jobInstanceId' = $searchResults.vmDocument.versions[$snapshotId].instanceId.jobInstanceId;
                'startTimeUsecs' = $searchResults.vmDocument.versions[$snapshotId].instanceId.jobStartTimeUsecs
            }
        );
        'mountVolumesParams' = @{
            'targetEntity' = $targetEntity;
            'vmwareParams' = @{
                'bringDisksOnline' = $false;
                }
            }
        }
} else {
    $mountTask = @{
        'name' = 'Kroll OnTrack recovery mount';
        'objects' = @(
            @{
                'jobId' = $searchResults.vmDocument.objectId.jobId;
                'jobUid' = $searchResults.vmDocument.objectId.jobUid;
                'entity' = $sourceEntity;
                'jobInstanceId' = $searchResults.vmDocument.versions[$snapshotId].instanceId.jobInstanceId;
                'startTimeUsecs' = $searchResults.vmDocument.versions[$snapshotId].instanceId.jobStartTimeUsecs
            }
        );
        'mountVolumesParams' = @{
            'targetEntity' = $targetEntity;
            'vmwareParams' = @{
                'bringDisksOnline' = $true;
                'targetEntityCredentials' = @{
                    'username' = $targetUsername;
                    'password' = $targetPw;
                }
            }
        }
    }
}


if($targetEntity.parentId ){
    $mountTask['restoreParentSource'] = @{ 'id' = $targetEntity.parentId }
}

Write-Host "Starting Instant Mount process to $targetServer .... wait!" -ForegroundColor Yellow
$result = api post /restore $mountTask
$taskid = $result.restoreTask.performRestoreTaskState.base.taskId

### monitor process until it is finished
do
{
    sleep 3
    $restoreTask = api get /restoretasks/$taskid
    $restoreTaskStatus = $restoreTask.restoreTask.performRestoreTaskState.base.publicStatus
} until ($restoreTaskStatus -in $finishedStates)

### check if mount was success
if($restoreTaskStatus -eq 'kSuccess'){
    $mountPoints = $restoreTask.restoreTask.performRestoreTaskState.mountVolumesTaskState.mountInfo.mountVolumeResultVec
    if ($online -eq 'true') {
        foreach($mountPoint in $mountPoints){
            Write-Host "$($mountPoint.originalVolumeName) mounted to $($mountPoint.mountPoint)" -ForegroundColor Yellow
        }
    }
}else{
    Write-Warning "mount operation ended with: $restoreTaskStatus"
}

### launch Kroll OnTrack
Write-Host "Start Kroll OnTrack and perform restore" -ForegroundColor Yellow

### tear down DB clones
$teardown = Read-Host 'Type YES to tear down mounts now'

if ($teardown -eq 'YES') {
    Write-Host "Tearing down mount...." -ForegroundColor Yellow
    $tearDownTask = api post /destroyclone/$($restoreTask.restoreTask.performRestoreTaskState.base.taskId)
} else {
    Write-Host "Mount is still running. You have to clean job manually" -ForegroundColor Yellow
}

Write-Host "Kroll Recovery process finished!" -ForegroundColor Yellow
