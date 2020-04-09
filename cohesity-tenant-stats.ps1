### usage: ./cohesity-tenant-stats.ps1 -vip 192.168.1.198 -username admin -export stats.csv

### Example script to get latest backuprun statistics per object - Jussi Jaurola <jussi@cohesity.com>

### Note! You need to have cohesity-api.ps1 on same directory!


### process commandline arguments
[CmdletBinding()]
param (
    [Parameter(Mandatory = $True)][string]$vip, #cohesity cluster vip
    [Parameter(Mandatory = $True)][string]$username,
    [Parameter(Mandatory = $True)][string]$export 
    )

### source the cohesity-api helper code and connect to cluster
try {
    . ./cohesity-api.ps1
    apiauth -vip $vip -username $username 
} catch {
    write-host "Cannot connect to cluster $vip" -ForegroundColor Yellow
    exit
}

### cluster Id
$clusterId = (api get cluster).id

# Write headers to CSV-file 
Add-Content -Path $export -Value "'Tenant','CustomerId','Tenant Storage Used','Source name','Source size','Last backup'"

$global:sources = api get "/entitiesOfType?acropolisEntityTypes=kVirtualMachine&adEntityTypes=kRootContainer&adEntityTypes=kDomainController&agentEntityTypes=kGroup&agentEntityTypes=kHost&allUnderHierarchy=true&awsEntityTypes=kEC2Instance&awsEntityTypes=kRDSInstance&azureEntityTypes=kVirtualMachine&environmentTypes=kAcropolis&environmentTypes=kAD&environmentTypes=kAWS&environmentTypes=kAgent&environmentTypes=kAzure&environmentTypes=kFlashblade&environmentTypes=kGCP&environmentTypes=kGenericNas&environmentTypes=kGPFS&environmentTypes=kHyperFlex&environmentTypes=kHyperV&environmentTypes=kIsilon&environmentTypes=kKVM&environmentTypes=kNetapp&environmentTypes=kO365&environmentTypes=kPhysical&environmentTypes=kPure&environmentTypes=kView&environmentTypes=kVMware&flashbladeEntityTypes=kFileSystem&gcpEntityTypes=kVirtualMachine&genericNasEntityTypes=kHost&gpfsEntityTypes=kFileset&hyperflexEntityTypes=kServer&hypervEntityTypes=kVirtualMachine&isProtected=true&isilonEntityTypes=kMountPoint&kvmEntityTypes=kVirtualMachine&netappEntityTypes=kVolume&office365EntityTypes=kOutlook&office365EntityTypes=kMailbox&office365EntityTypes=kUsers&office365EntityTypes=kGroups&office365EntityTypes=kSites&office365EntityTypes=kUser&office365EntityTypes=kGroup&office365EntityTypes=kSite&oracleEntityTypes=kDatabase&physicalEntityTypes=kHost&physicalEntityTypes=kWindowsCluster&physicalEntityTypes=kOracleRACCluster&physicalEntityTypes=kOracleAPCluster&pureEntityTypes=kVolume&sqlEntityTypes=kDatabase&viewEntityTypes=kView&viewEntityTypes=kViewBox&vmwareEntityTypes=kVirtualMachine" | select-object id, displayName

$tenants = api get "tenants?properties=Entity"
$vaults = api get vaults

foreach ($tenant in $tenants) {
    $tenantId = $tenant.tenantId
    $tenantName = $tenant.name
    $customerId = $tenant.description
    $tenantSources = $sources | Where-Object tenantId -eq $tenantId
    $tenantVault = $vaults | Where name -CMatch $tenantName

    $vaultStats = api get "reports/dataTransferToVaults?vaultIds=$($tenantVault.id)"
    $tenantStorageUsed = $vaultStats.dataTransferSummary.storageConsumedBytes

    foreach ($entity in $tenant.entityIds) {
        $source = $sources | Where-Object id -eq $entity

        if ($source) {
            $sourceName = $source.displayName
            $stats = api get "reports/protectionSourcesJobRuns?protectionSourceIds=$($ts.entity.id)&excludeNonRestoreableRuns"

            if ($stats) { 
                $successRuns = $stats.protectionSourceJobRuns.snapshotsInfo | Where-Object runStatus -eq 'kSuccess'
                $lastJobRunTime =  Get-Date (usecsToDate $($successRuns[0].jobRunStartTimeUsecs)) -Format "dd.M.yyy HH.mm:ss"
                $sourceSize = $successRuns[0].numLogicalBytesProtected

                $line = "'{0}','{1}','{2}','{3}','{4}','{5}'" -f $tenantId, $customerId, $tenantStorageUsed, $sourceName, $sourceSize, $lastJobRunTime
                Add-Content -Path $export -Value $line
            } else {
                Add-Content -Path "error.log" -Value "No success runs for $sourceName under tenant $tenantName"
            }
        } else {
            Add-Content -Path "error.log" -Value "Entity $entity is not protected under tenant $tenantName" 
        }
         
    }
}
