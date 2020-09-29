### Example script to get cluster stats from local clusters - Jussi Jaurola <jussi@cohesity.com

### clusters-file should contain fqdn/vip for connection per line:
###
### cluster1.test.local
### cluster2.my.org
### cluster3.my.org


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

### Add headers to export-file
Add-Content -Path $export -Value "Cluster Name, Tenant Name, Tenant StorageDomain(s), Tenant Storage Consumed, Tenant Protected Object, Tenant Protected Capacity"

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
        $tenantStorageDomain = ""
        $tenantStorageConsumedBytes = 0

        $tenantName = $tenant.name
        $tenantId = $tenant.tenantId
        $tenantId = $tenantId.Substring(0,$tenantId.Length-1)

        Write-Host "Getting stats for tenant $tenantName"

        apiauth -vip $cluster -username $username -tenantId $tenantId     
        
        $tenantProtectionSources = api get "protectionSources/registrationInfo?includeEntityPermissionInfo=true"
        $tenantProtectedObjects = $tenantProtectionSources.stats.protectedCount
        $tenantProtectedCapacity = [math]::Round(($tenantProtectionSources.stats.protectedSize/1TB),1)

        ### Get storagedomain stats
        $storageConsumed = api get "/reports/tenantStorage?allUnderHierarchy=true"
        
        foreach ($storageInfo in $storageConsumed.tenantStorageInformation) {
            $tenantStorageDomain += $storageInfo.viewBoxName + " "
            $tenantStorageConsumedBytes += [math]::Round(($storageInfo.backupPhysicalSizeBytes/1TB),1)
        }

        ### write data 
        $line = "{0},{1},{2},{3},{4},{5}" -f $clusterName, $tenantName, $tenantStorageDomain, $tenantStorageConsumedBytes, $tenantProtectedObjects, $tenantProtectedCapacity
        Add-Content -Path $export -Value $line

    }

}
