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
Add-Content -Path $export -Value "Cluster, dataPlatform, cloudArchive, cloudTier, cloudSpin, dataProtect"

$clusters = $HELIOSCONNECTEDCLUSTERS.name
foreach ($cluster in $clusters) {
    ## Connect to cluster
    Write-Host "Collecting license usage for cluster $cluster"
    heliosCluster $cluster

    $clusterInfo = api get cluster
    $licenseUsage = api get /nexus/license/account_usage | Select-Object usage

    $used = $licenseUsage.usage.$($clusterInfo.id)

    $globalLicenseUsages[$cluster] = @{}

    foreach ($use in $used) {
        $globalLicenseUsages[$cluster][$($use.featureName)] = $use.currentUsageGiB
    }
}

Write-Host "Exporting license usages to $export"
$globalLicenseUsages.GetEnumerator() | ForEach-Object {
    $line = "{0},{1},{2},{3},{4},{5}" -f $_.Name, $_.Value.dataPlatform, $_.Value.cloudArchive, $_.Value.cloudTier, $_.Value.cloudSpin, $_.Value.dataProtect 
    Add-Content -Path $export -Value $line   
}
