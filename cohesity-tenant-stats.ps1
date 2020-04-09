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

### usecs for dates
$weekAgo = dateToUsecs (Get-Date -hour 0 -minute 0 -second 0).AddDays(-7)
$yesterday = dateToUsecs (Get-Date -hour 0 -minute 0 -second 0).AddDays(-1)
$today = dateToUsecs (Get-Date -hour 0 -minute 0 -second 0)

$global:sources = api get "/reports/objects/storage"
$tenants = api get tenants
$vaults = api get vaults

foreach ($tenant in $tenants) {
    $tenantId = $tenant.tenantId
    $tenantName = $tenant.name
    $customerId = $tenant.description
    $tenantSources = $sources | Where-Object tenantId -eq $tenantId
    $tenantVault = $vaults | Where name -CMatch $tenantName

    $vaultStats = api get "reports/dataTransferToVaults?vaultIds=$($tenantVault.id)"
    $tenantStorageUsed = $vaultStats.dataTransferSummary.storageConsumedBytes

    foreach ($ts in $tenantSources) {
        $stats = api get "reports/protectionSourcesJobRuns?protectionSourceIds=$($ts.entity.id)&excludeNonRestoreableRuns" 

        $successRuns = $stats.protectionSourceJobRuns.snapshotsInfo | Where-Object runStatus -eq 'kSuccess'
        $lastJobRunTime =  Get-Date (usecsToDate $($successRuns[0].lastRunEndTimeUsecs)) -Format "dd.M.yyy HH.mm:ss"
        $sourceSize = $successRuns[0].numLogicalBytesProtected
        $sourceName = $ts.name

        $line = "'{0}','{1}','{2}','{3}','{4}','{5}'" -f $tenantId, $customerId, $tenantStorageUsed, $sourceName, $sourceSize, $lastJobRunTime
        Add-Content -Path $export -Value $line

    }
}
