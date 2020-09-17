### Example script to get cluster stats from local clusters - Jussi Jaurola <jussi@cohesity.com

### Note! You need to have cohesity-api.ps1 on same directory!


### process commandline arguments
[CmdletBinding()]
param (
    [Parameter(Mandatory = $True)][string]$clusters, 
    [Parameter(Mandatory = $True)][string]$username,
    [Parameter(Mandatory = $true)][string]$export 
    )

### Get clusters from file
try {
    $clusterlist = Get-Content $clusters
} catch {
    write-host "Cannot open clusters file $clusters" -ForegroundColor Yellow
    exit
}
### source the cohesity-api helper code 
. ./cohesity-api.ps1

foreach ($cluster in $clusterlist) {
    Write-Host "Reading stats from cluster $cluster"

    try {
        apiauth -vip $cluster -username $username 
        $clusterName = (api get cluster).name
    } catch {
        write-host "Cannot connect to cluster $vip" -ForegroundColor Yellow
        exit
    }

    ### Get tentants
    $tenants = api get tenants

    foreach ($tenant in $tenants) {
        $tenantName = $tenant.name
        $tenantId = $tenant.tenantId
        $tenantId = $tenantId.Substring(0,$tenantId.Length-1)

        Write-Host "Getting stats for tenant $tenantName"

        apiauth -vip $cluster -username $username -tenantId $tenantId     
        
        $tenantProtectionSources = api get "protectionSources/registrationInfo?includeEntityPermissionInfo=true"
        $tenantProtectedObjects = $tenantProtectionSources.stats.protectedCount
        $tenantProtectedCapacity = $tenantProtectionSources.stats.protectedSize

        ### Get storagedomain stats
        $storageConsumed = api get "/reports/tenantStorage?allUnderHierarchy=true"

        $tenantStorageDomain = $storageConsumed.tenantStorageInformation.viewBoxName
        $tenantStorageConsumedBytes =  $storageConsumed.tenantStorageInformation.backupPhysicalSizeBytes

        ### write data 
        $line = "{0},{1},{2},{3},{4},{5}" -f $clusterName, $tenantName, $tenantStorageDomain, $tenantStorageConsumedBytes, $tenantProtectedObjects, $tenantProtectedCapacity
        Add-Content -Path $export -Value $line

    }

}
