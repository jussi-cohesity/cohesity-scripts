### Example script to get license usages from helios - Jussi Jaurola <jussi@cohesity.com>

### Note! You need to have cohesity-api.ps1 on same directory! 
##
## https://github.com/bseltz-cohesity/scripts/tree/master/powershell/cohesity-api

### Units listed are GiB (Valid up to 6.6.0b release)

### process commandline arguments
[CmdletBinding()]
param (
    [Parameter(Mandatory = $True)][string]$cluster, 
    [Parameter(Mandatory = $True)][string]$username,
    [Parameter()][string]$domain = 'local',
    )

### source the cohesity-api helper code 
. $(Join-Path -Path $PSScriptRoot -ChildPath cohesity-api.ps1)

try {
    apiauth -vip $cluster -username $username -domain $domain
    $clusterName = (api get cluster).name
} catch {
    write-host "Cannot connect to cluster $vip" -ForegroundColor Yellow
    exit
}

$globalLicenseUsages = @{}

### Add headers to export-file
Add-Content -Path $export -Value "Cluster, dataPlatform, cloudArchive, cloudTier, cloudSpin, dataProtect, archive, smartFiles, dataProtectReplica, dataProtectService"

Write-Host "Collecting license usage for cluster $cluster"

$clusterInfo = api get cluster
$cluster = $($clusterInfo.name)
$licenseUsage = api get /nexus/license/account_usage | Select-Object usage
$export = $($clusterInfo.name) + "_" + $($clusterInfo.id) + "_licenseusage.csv"
$used = $licenseUsage.usage.$($clusterInfo.id)

$globalLicenseUsages[$cluster] = @{}

foreach ($use in $used) {
    $globalLicenseUsages[$cluster][$($use.featureName)] = $use.currentUsageGiB
}

Write-Host "Exporting license usages to $export"
$globalLicenseUsages.GetEnumerator() | ForEach-Object {
    $line = "{0},{1},{2},{3},{4},{5},{6},{7},{8},{9}" -f $_.Name, $_.Value.dataPlatform, $_.Value.cloudArchive, $_.Value.cloudTier, $_.Value.cloudSpin, $_.Value.dataProtect, $_.Value.archive, $_.Value.smartFiles, $_.Value.dataProtectReplica, $_.Value.dataProtectService 
    Add-Content -Path $export -Value $line   
}
