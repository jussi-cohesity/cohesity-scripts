### usage: ./cloudRetrieve.ps1 -vip 192.168.1.198 -username admin [ -domain local ] -externalTarget targetname -startDate 'mm/dd/yyyy' -endDate 'mm/dd/yyyy' [-retrieve true] [-storageDomain 'domainanme'] [-jobNames job1,job2,job3]

### Sample script to do CloudRetrieve - Jussi Jaurola <jussi@cohesity.com>

### If retrieve is defined, script will automatically retrieve _latest_ backup from cloud

## process commandline arguments
[CmdletBinding()]
param (
    [Parameter(Mandatory = $True)][string]$vip,
    [Parameter(Mandatory = $True)][string]$username,
    [Parameter()][string]$domain = 'local',
    [Parameter(Mandatory = $True)][string]$externalTarget,
    [Parameter(Mandatory = $True)][string]$startDate,
    [Parameter(Mandatory = $True)][string]$endDate,
    [Parameter()][ValidateSet('true','false')][string]$retrieve = "false",
    [Parameter(Mandatory = $True)][string]$storageDomain,
    [Parameter(Mandatory = $True)][string]$jobNames
)

### source the cohesity-api helper code
. ./cohesity-api

### startDate and endDate to usecs
try {
    $startDate = [int64](dateToUsecs $startDate)
} catch {
    write-host "Given startDate is not valid. Please use mm/dd/yyyyy" -ForegroundColor Red
    exit
}
try {
    $endDate = [int64](dateToUsecs $endDate)
} catch {
    write-host "Given endDate is not valid. Please use mm/dd/yyyyy" -ForegroundColor Red
    exit
}

### authenticate
try {
    Write-Host "$(Get-Date -Format "dd.mm.yyyy HH.mm"): Connecting to Cohesity Cluster $vip with username $username" -ForegroundColor Yellow
    apiauth -vip $vip -username $username -domain $domain
} catch {
    write-host "Cannot connect to Cohesity cluster $vip" -ForegroundColor Red
    exit
}


### get storageDomain info
$viewBox = api get viewBoxes | where-object { $_.name -eq $storageDomain }

### get vault
Write-Host "$(Get-Date -Format "dd.mm.yyyy HH.mm"): Searching external target with name $externalTarget" -ForegroundColor Yellow
$vault = api get vaults | where-object { $_.name -eq $externalTarget }
if (!$vault) { 
    write-host "Couldnt find externalTarget $externalTarget. Please check!" -ForegroundColor Red
    exit
}

$searchTask = @{
    "endTimeUsecs" = [int64]$endDate;
    "startTimeUsecs" = [int64]$startDate;
    "searchJobName" = "CloudRetrieveSearch_" + $externalTarget + "_" + $((get-date).ToString().Replace('/', '_').Replace(':', '_').Replace(' ', '_'));
    "vaultId" = $vault.Id;
}

Write-Host "$(Get-Date -Format "dd.mm.yyyy HH.mm"): Running CloudRetrieve search job for $externalTarget. This might take from few minutes to hours. PLease wait! Checking status every 5 minutes." -ForegroundColor Yellow
$searchJob = api post remoteVaults/searchJobs $searchTask

### Get search task status and wait until it is done
$status = 0
Do {
    Start-Sleep -Seconds 300
    Write-Host "$(Get-Date -Format "dd.mm.yyyy HH.mm)": Checking status of CloudRetrieve Search job" -ForegroundColor Yellow    
    $searchStatus = api get "remoteVaults/searchJobs/$($searchJob.id)"
    if ($searchStatus.searchJobStatus -eq "kJobSucceeded") {
        $status = 1
        Write-Host "$(Get-Date -Format 'dd.mm.yyyy HH.mm'): Search is done" -ForegroundColor Yellow
    } else {
        Write-Host "$(Get-Date -Format "dd.mm.yyyy HH.mm"): Job is still running. Sleeping 5 minutes." -ForegroundColor Yellow
    }
} Until ($status -eq "1")

### if retrieve is selected do actual retrieve also
if ($retrieve -eq 'true') {
    Write-Host "$(Get-Date -Format "dd.mm.yyyy HH.mm"): Getting job information from CloudRetrieve search" -ForegroundColor Yellow  
    $recoveryTask =  api get "remoteVaults/searchJobResults?clusterId=$($searchJob.clusterId)&clusterIncarnationId=$($searchJob.clusterIncarnationId)&searchJobId=$($searchJob.id)" 
    $searchJobUid = @{
        "clusterId" = $($searchJob.clusterId);
        "clusterIncarnationId" = $($searchJob.clusterIncarnationId);
        "id" = $($searchJob.id);
    }


    ### get protection jobs from 
    $restoreObjects = @()
    foreach ($job in $jobNames.split(",")) {
        $jobDetails = $recoveryTask.protectionJobs |  where-object { $_.jobname -eq $job }
        if ($jobDetails)
        {
            Write-Host "$(Get-Date -Format "dd.mm.yyyy HH.mm"): Found job $($jobDetails.jobName) from search. Adding to retrieve job!" -ForegroundColor Yellow  
            $thisArchiveTaskUid = @{
                "clusterId" = $($jobDetails.protectionJobRuns.archiveTaskUid.clusterId[-1]);
                "clusterIncarnationId" = $($jobDetails.protectionJobRuns.archiveTaskUid.clusterIncarnationId[-1]);
                "id" = $($jobDetails.protectionJobRuns.archiveTaskUid.id[-1]);
            }

            $thisRemoteProtectionJobUid = @{
                "clusterId" = $($jobDetails.jobUid.clusterId[-1]);
                "clusterIncarnationId" = $($jobDetails.jobUid.clusterIncarnationId[-1]);
                "id" = $($jobDetails.jobUid.id[-1]);
            }

            $restoreObjects += @{
                "archiveTaskUid" = $thisArchiveTaskUid;
                "endTimeUsecs" = $recoveryTask.endTimeUsecs;
                "remoteProtectionJobUid" = $thisRemoteProtectionJobUid;
                "startTimeUsecs" = $recoveryTask.startTimeUsecs;
                "viewBoxId" = $viewBox.id
            }
        } else {
            Write-Host "$(Get-Date -Format "dd.mm.yyyy HH.mm"): Could not find $job from search" -ForegroundColor Red
        }
    }

    if (!$restoreObjects) { 
        Write-Host "$(Get-Date -Format "dd.mm.yyyy HH.mm"): No objects found for restore!" -ForegroundColor Red
    } else
    {
        ### build job retrieve json
        Write-Host "$(Get-Date -Format "dd.mm.yyyy HH.mm"): Running retrieve job" -ForegroundColor Yellow  
        $retrieveJson = D@{
            "glacierRetrievalType" = "kStandard";
            "restoreObjects" = $restoreObjects;
            "searchJobUid" = $searchJobUid;
            "taskName" = "CloudRetrieve_" + $externalTarget + "_" + $((get-date).ToString().Replace('/', '_').Replace(':', '_').Replace(' ', '_'));
            "vaultId" = $($vault.Id);
        }
        $retrieveJson = api post /public/remoteVaults/restoreTasks $retrieveJson
    }
}


