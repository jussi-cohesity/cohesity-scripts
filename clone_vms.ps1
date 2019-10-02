### usage: ./clone-vms.ps1 -vip 192.168.1.198 -username admin [ -domain local ] -target 'vcenter' -viewName 'backupview' -jobName 'Virtual'

### process commandline arguments
[CmdletBinding()]
param (
    [Parameter(Mandatory = $True)][string]$vip,
    [Parameter(Mandatory = $True)][string]$username,
    [Parameter(Mandatory = $True)][string]$target,
    [Parameter()][string]$domain = 'local',
    [Parameter(Mandatory = $True)][string]$viewName,
    [Parameter(Mandatory = $True)][string]$jobName
)

### source the cohesity-api helper code
. ./cohesity-api

### authenticate
apiauth -vip $vip -username $username -domain $domain

### search target and datastore
$sources = api get protectionSources?"environments=kVMware&allUnderHierarchy=true"       
$newtarget = $sources.protectionSource | where name -match $target

if (!$newtarget) {
    write-host "No registered source found with name $target" -ForegroundColor Yellow
    exit
}
$newParentId = $newtarget.id

$resources = api get /resourcePools?vCenterId=$newParentId
$resourcePoolId = $resources.resourcePool.id

if (!$resourcePoolId){
    write-host "No resourcepool found for target $target" -ForegroundColor Yellow
    exit
}

### search for VMs to clone

$jobs = api get protectionJobs | Where-Object {$_.name -ieq $jobName}
$jobId = $jobs.Id
$vms = $jobs.sourceIds
$vmcount = $vms.count

if ($vms) {

    $runs = api get protectionRuns?"jobId=$jobId&excludeNonRestoreableRuns=true"
    
    $latestrun = $runs.backupRun[0]
    $latestrundate = usecsToDate $runs.backupRun.stats.startTimeUsecs[0]
    write-host "Backup job $jobName contains $vmcount VMs"
    write-host "Latest recoverable snapshot for job is $latestrundate"

    ### fetch list of VMs for source
    $vmlist = api get protectionSources/virtualMachines?vCenterId=$($jobs.parentSourceId)

    ### clone each vm from latest run of backupjob
    $objects = @()
    foreach ($vm in $vms){
        $a = $vmlist | Where-Object {$_.id -ieq $vm}
        $vm_name = $a.Name
        write-host "Adding $vm_name to clone task"
        $objects += @{
            "jobId" = $jobs.Id;
            "protectionSourceId" = $vm; 
        }
    }

    $clonetask = @{
        "name"  = "BackupExport_" + $((get-date).ToString().Replace('/', '_').Replace(':', '_').Replace(' ', '_'));
        "objects"   = $objects;
        "type" = "kCloneVMs";
            "newParentId" = $newParentId;
            "targetViewName" = $viewName;
        "continueOnError" = $true;
        "vmwareParameters"  = @{
            "disableNetwork" = $true;
            "poweredOn" = $false;
            "prefix" =  "export-";
            "resourcePoolId" = $resourcePoolId;
        }
    }

    write-host "Running rest-api command:"
    $clonetask | ConvertTo-Json
    $cloneoperation = api post restore/clone $clonetask

    if ($cloneoperation) {
        write-host "Cloned VMs!"
    }

}
else {
    write-host "Cannot find backupjob with VMs" -ForegroundColor Yellow
}
