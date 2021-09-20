### Example script to get estimate for license consumers per tenant from helios - Jussi Jaurola <jussi@cohesity.com>

### Note! You need to have cohesity-api.ps1 on same directory!

### process commandline arguments
[CmdletBinding()]
param (
    [Parameter(Mandatory = $True)][string]$apikey,
    [Parameter()][ValidateSet('MB','GB','TB')][string]$unit = "TB",
    [Parameter(Mandatory = $true)][string]$export 
    )


### source the cohesity-api helper code 
. ./cohesity-api.ps1

try {
    apiauth -helios -password $apikey
} catch {
    write-host "Cannot connect to Helios. Please check the apikey!" -ForegroundColor Red
    exit
}

### Add headers to export-file
Add-Content -Path $export -Value "Cluster Name, Tenant Name, DataPlatform Used ($unit), DataProtect Used ($unit), CloudArchive Used ($unit)"

$units = "1" + $unit

$clusters = $HELIOSCONNECTEDCLUSTERS.name
foreach ($cluster in $clusters) {
    ## Conenct to cluster
    Write-Host "Connecting to cluster $cluster" -ForegroundColor Yellow

    heliosCluster $cluster
    
    $stats = api get "stats/tenants?allUnderHierarchy=true&maxCount=1000&skipGroupByTenant=true"
    
    foreach ($stat in $stats.statsList) {

        $tenantName = $stat.name
        Write-Host "    Collecting stats for $tenantName" -ForegroundColor Yellow

        $dataPlatformUsed = $stat.stats.localDataWrittenBytes/$units
        $dataProtectUsed = $stat.stats.localDataWrittenBytes/$units
        $cloudArchiveUsed = $stat.stats.cloudTotalPhysicalUsageBytes/$units    

        ### write data 
        $line = "{0},{1},{2},{3},{4}" -f $cluster, $tenantName, $dataPlatformUsed, $dataProtectUsed, $cloudArchiveUsed
        Add-Content -Path $export -Value $line
    }    
}
