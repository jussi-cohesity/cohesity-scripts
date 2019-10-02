### usage: ./deleteCloneTask.ps1 -vip 192.168.1.198 -username admin [ -domain local ] -taskName

### process commandline arguments
[CmdletBinding()]
param (
    [Parameter(Mandatory = $True)][string]$vip, #the cluster to connect to (DNS name or IP)
    [Parameter(Mandatory = $True)][string]$username, #username (local or AD)
    [Parameter()][string]$domain = 'local', #local or AD domain
    [Parameter(Mandatory = $True)][string]$taskName
)

### source the cohesity-api helper code
. ./cohesity-api

### authenticate
apiauth -vip $vip -username $username -domain $domain

$task = api get /restoretasks?restoreTypes=kCloneVMs | where-object { $_.restoreTask.destroyClonedTaskStateVec -eq $null } | where-object { $_.restoreTask.performRestoreTaskState.base.name -eq $taskName}

if ($task) {
    $taskId = $task.restoreTask.performRestoreTaskState.base.taskId
    write-host "Tearing down cloneTask $taskName with id $taskId"
    $result = api post "/destroyclone/$taskId"
} else {
    write-host "Cannot find active cloneTask $taskName" -ForegroundColor Yellow
}