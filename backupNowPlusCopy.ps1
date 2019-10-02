### usage: ./backupNowPlusCopy.ps1 -vip 192.168.1.198 -username admin [ -domain local ] -jobName 'Virtual' [-printJson 'false']

### Run protectionJob and its replication jobs - Jussi Jaurola <jussi@cohesity.com>

### process commandline arguments
[CmdletBinding()]
param (
    [Parameter(Mandatory = $True)][string]$vip,
    [Parameter(Mandatory = $True)][string]$username,
    [Parameter()][string]$domain = 'local',
    [Parameter(Mandatory = $True)][string]$jobName,
    [Parameter()][ValidateSet('true','false')][string]$printJson = "false"
)

### source the cohesity-api helper code
. ./cohesity-api

### authenticate
apiauth -vip $vip -username $username -domain $domain

### find job with name
$job = api get protectionJobs | where name -match $jobName

if (!$job) {
    write-host "No job found with name $jobName" -ForegroundColor Yellow
    exit
}

$jobId = $job.Id
### get policy and replication retention period for job
$policyId = $job.policyId
$policy = api get protectionPolicies/$policyId

if (!$policy) {
    write-host "Job $jobName uses policy with policyid $policyId which is not found" -ForegroundColor Yellow
    exit
}

$snapshotArchivalCopyPolicies = $policy.snapshotArchivalCopyPolicies

$replicationCopyPolicies = $policy.snapshotReplicationCopyPolicies
$copyRunTargets = @()

### List replication targets and retention times for policy

if ($replicationCopyPolicies) {
    $replicationCopyPolicies | Foreach {
        $daysToKeep = $_.daysToKeep
        $targetClusterId = $_.target.clusterId
        $targetClusterName = $_.target.clusterName
        write-host "Replication target for job $jobName is $targetClusterName with id $targetClusterId. Keeping copy $daysToKeep days." 
    
        $copyRunTargets += @{
            "daysToKeep" = $daysToKeep;
            "replicationTarget"  =@{
                "clusterId" = $targetClusterId;
                "clusterName" = $targetClusterName;
            }
            "type" =  "kRemote" ;
        }
    
    }
}

### List archive targets and retention times for policy
if ($snapshotArchivalCopyPolicies) {
    $snapshotArchivalCopyPolicies| Foreach {
        $daysToKeep = $_.daysToKeep
        $targetVaultId = $_.target.vaultId
        $targetVaultName = $_.target.vaultName
        write-host "Archive target for $jobName is $targetVaultName with id $targetVaultId. Keeping copy $daysToKeep days."

        $copyRunTargets += @{
            "daysToKeep" = $daysToKeep;
            "archivalTarget"  =@{
                "vaultId" = $targetVaultId;
                "vaultName" = $targetVaultName;
                "vaultType" = "kCloud"
            }
            "type" =  "kArchival" ;
        }
    }
}

if ($copyRunTargets)
{
    $sourceIds = @()
    $jobData = @{
        "copyRunTargets"  = $copyRunTargets;
        "sourceIds" = $sourceIds;
        "runType" = "kRegular"
    }
}

write-host "Running job $jobName..."  -ForegroundColor Yellow
if ($printJson -eq "true") { $jobData | ConvertTo-Json -Depth 3}
$run = api post protectionJobs/run/$jobId $jobData
