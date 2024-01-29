### Example script to get license usages from helios - Jussi Jaurola <jussi@cohesity.com>

### Note! You need to have cohesity-api.ps1 on same directory! Units listed are GiB (Valid up to 6.6.0b release)

### process commandline arguments
[CmdletBinding()]
param (
    [Parameter(Mandatory = $True)][string]$apikey,
    [Parameter(Mandatory = $true)][string]$export 
    )


### source the cohesity-api helper code 
. ./cohesity-api.ps1

try {
    apiauth -helios -password $apikey
} catch {
    write-host "Cannot connect to Helios. Please check the apikey!" -ForegroundColor Yellow
    exit
}

$globalLicenseUsages = @{}

### Add headers to export-file
Add-Content -Path $export -Value "Cluster, dataPlatform, cloudArchive, cloudTier, cloudSpin, dataProtect, archive, smartFiles, dataProtectReplica, dataProtectService"

$clusters = heliosClusters 
$usage = api get -mcm minos/licensing/v1/account/usage

foreach ($cluster in $clusters) {

    $clusterName = $cluster.name
    ## Connect to cluster
    Write-Host "Collecting license usage for cluster $clusterName"

    $used = $usage.usage.$($cluster.clusterId)

    $globalLicenseUsages[$clusterName] = @{}

    foreach ($use in $used) {
        $globalLicenseUsages[$clusterName][$($use.featureName)] = $use.currentUsageGiB
    }
}

Write-Host "Exporting license usages to $export"
$globalLicenseUsages.GetEnumerator() | ForEach-Object {
    $line = "{0},{1},{2},{3},{4},{5},{6},{7},{8},{9}" -f $_.Name, $_.Value.dataPlatform, $_.Value.cloudArchive, $_.Value.cloudTier, $_.Value.cloudSpin, $_.Value.dataProtect, $_.Value.archive, $_.Value.smartFiles, $_.Value.dataProtectReplica, $_.Value.dataProtectService 
    Add-Content -Path $export -Value $line   
}
