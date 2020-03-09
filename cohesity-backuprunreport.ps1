### usage: ./cohesity-backuprunreport.ps1 -vip 192.168.1.198 -username admin [-export stats.csv]

### Example script to get latest backuprun statistics per object - Jussi Jaurola <jussi@cohesity.com>

### Note! You need to have cohesity-api.ps1 on same directory!


### process commandline arguments
[CmdletBinding()]
param (
    [Parameter(Mandatory = $True)][string]$vip, #cohesity cluster vip
    [Parameter(Mandatory = $True)][string]$username,
    [Parameter()][string]$export 
    )

### source the cohesity-api helper code and connect to cluster
try {
    . ./cohesity-api
    apiauth -vip $vip -username $username 
} catch {
    write-host "Cannot connect to cluster $vip" -ForegroundColor Yellow
    exit
}

### cluster Id
$clusterId = (api get cluster).id

if ($export) {
    # Write headers to CSV-file 
    Add-Content -Path $export -Value "'Object','Status','Start time','End time','Transfered bytes','Backup type','Expiration date'"
}
# $sources = api get "/entitiesOfType?acropolisEntityTypes=kVirtualMachine&adEntityTypes=kRootContainer&adEntityTypes=kDomainController&agentEntityTypes=kGroup&agentEntityTypes=kHost&allUnderHierarchy=true&awsEntityTypes=kEC2Instance&awsEntityTypes=kRDSInstance&azureEntityTypes=kVirtualMachine&environmentTypes=kAcropolis&environmentTypes=kAD&environmentTypes=kAWS&environmentTypes=kAgent&environmentTypes=kAzure&environmentTypes=kFlashblade&environmentTypes=kGCP&environmentTypes=kGenericNas&environmentTypes=kGPFS&environmentTypes=kHyperFlex&environmentTypes=kHyperV&environmentTypes=kIsilon&environmentTypes=kKVM&environmentTypes=kNetapp&environmentTypes=kO365&environmentTypes=kOracle&environmentTypes=kPhysical&environmentTypes=kPure&environmentTypes=kSQL&environmentTypes=kView&environmentTypes=kVMware&flashbladeEntityTypes=kFileSystem&gcpEntityTypes=kVirtualMachine&genericNasEntityTypes=kHost&gpfsEntityTypes=kFileset&hyperflexEntityTypes=kServer&hypervEntityTypes=kVirtualMachine&isProtected=true&isilonEntityTypes=kMountPoint&kvmEntityTypes=kVirtualMachine&netappEntityTypes=kVolume&office365EntityTypes=kOutlook&office365EntityTypes=kMailbox&office365EntityTypes=kUsers&office365EntityTypes=kGroups&office365EntityTypes=kSites&office365EntityTypes=kUser&office365EntityTypes=kGroup&office365EntityTypes=kSite&oracleEntityTypes=kDatabase&physicalEntityTypes=kHost&physicalEntityTypes=kWindowsCluster&physicalEntityTypes=kOracleRACCluster&physicalEntityTypes=kOracleAPCluster&pureEntityTypes=kVolume&sqlEntityTypes=kDatabase&viewEntityTypes=kView&viewEntityTypes=kViewBox&vmwareEntityTypes=kVirtualMachine" | select-object id, displayName

$sources = api get "/entitiesOfType?acropolisEntityTypes=kVirtualMachine&adEntityTypes=kRootContainer&adEntityTypes=kDomainController&agentEntityTypes=kGroup&agentEntityTypes=kHost&allUnderHierarchy=true&awsEntityTypes=kEC2Instance&awsEntityTypes=kRDSInstance&azureEntityTypes=kVirtualMachine&environmentTypes=kAcropolis&environmentTypes=kAD&environmentTypes=kAWS&environmentTypes=kAgent&environmentTypes=kAzure&environmentTypes=kFlashblade&environmentTypes=kGCP&environmentTypes=kGenericNas&environmentTypes=kGPFS&environmentTypes=kHyperFlex&environmentTypes=kHyperV&environmentTypes=kIsilon&environmentTypes=kKVM&environmentTypes=kNetapp&environmentTypes=kO365&environmentTypes=kPhysical&environmentTypes=kPure&environmentTypes=kView&environmentTypes=kVMware&flashbladeEntityTypes=kFileSystem&gcpEntityTypes=kVirtualMachine&genericNasEntityTypes=kHost&gpfsEntityTypes=kFileset&hyperflexEntityTypes=kServer&hypervEntityTypes=kVirtualMachine&isProtected=true&isilonEntityTypes=kMountPoint&kvmEntityTypes=kVirtualMachine&netappEntityTypes=kVolume&office365EntityTypes=kOutlook&office365EntityTypes=kMailbox&office365EntityTypes=kUsers&office365EntityTypes=kGroups&office365EntityTypes=kSites&office365EntityTypes=kUser&office365EntityTypes=kGroup&office365EntityTypes=kSite&oracleEntityTypes=kDatabase&physicalEntityTypes=kHost&physicalEntityTypes=kWindowsCluster&physicalEntityTypes=kOracleRACCluster&physicalEntityTypes=kOracleAPCluster&pureEntityTypes=kVolume&sqlEntityTypes=kDatabase&viewEntityTypes=kView&viewEntityTypes=kViewBox&vmwareEntityTypes=kVirtualMachine" | select-object id, displayName

foreach ($source in $sources) {
    $stats = api get "reports/protectionSourcesJobRuns?protectionSourceIds=$($source.id)"  
    
    $object = $($source.displayName)

    write-host "Collecting stats for $object"
    $lastRunStartTimeUsecs = $stats.protectionSourceJobRuns.snapshotsInfo[0].lastRunStartTimeUsecs
    $lastRunStartTime = Get-Date (usecsToDate $lastRunStartTimeUsecs) -Format "MMM dd, yyyy HH:mm:ss"

    $lastRunEndTimeUsecs = $stats.protectionSourceJobRuns.snapshotsInfo[0].lastRunEndTimeUsecs
    $lastRunEndTime = Get-Date (usecsToDate $lastRunEndTimeUsecs) -Format "MMM dd, yyyy HH:mm:ss"

    $runSatus = $stats.protectionSourceJobRuns.snapshotsInfo[0].runSatus
    $runType = $stats.protectionSourceJobRuns.snapshotsInfo[0].runType
    $transferedBytes = $stats.protectionSourceJobRuns.snapshotsInfo[0].numBytesRead

    ## expiry date
    $jobId =  $stats.protectionSourceJobRuns.snapshotsInfo.jobId[0]
    $expdata = api get "/backupjobruns?allUnderHierarchy=true&exactMatchStartTimeUsecs=$($lastRunStartTimeUsecs)&excludeTasks=true&id=$($jobId)"
    $expiryTimeUsecs = $expdata.backupJobRuns.protectionRuns.copyRun.finishedTasks.expiryTimeUsecs 
    $expiryTime = Get-Date (usecsToDate $expiryTimeUSecs) -Format "MMM dd, yyyy HH:mm:ss"

    if ($export) {
        ## write data 
       
        $line = "'{0}','{1}','{2}','{3}','{4}','{5}','{6}'" -f $object, $runStatus, $lastRunStartTime, $lastRunEndTime, $transferedBytes, $runType, $expiryTime
        Add-Content -Path $export -Value $line
    }
}
