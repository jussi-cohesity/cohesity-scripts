### Example script to report storage size for protection group - Jussi Jaurola <jussi@cohesity.com>

### Note! You need to have cohesity-api.ps1 on same directory! 

### process commandline arguments
[CmdletBinding()]
param (
    [Parameter(Mandatory = $True)][string]$apikey,
    [Parameter(Mandatory = $True)][string]$export
    )

### source the cohesity-api helper code 
. ./cohesity-api.ps1

try {
    apiauth -helios -password $apikey
} catch {
    write-host "Cannot connect to Helios. Please check the apikey!" -ForegroundColor Yellow
    exit
}

$clusters = (heliosClusters).name
$report = @{}

foreach ($cluster in $clusters) {
    ## Connect to cluster
    Write-Host "Connecting to cluster $cluster" -ForegroundColor Yellow
    
    heliosCluster $cluster

    Write-Host "   Getting objects for cluster $cluster" -ForegroundColor Yellow
    
    $stats = (api get "stats/consumers?msecsBeforeCurrentTimeToCompare=604800000&maxCount=1000&fetchViewBoxName=true&fetchTenantName=true&fetchProtectionEnvironment=true&consumerType=kProtectionRuns").statsList

    foreach($stat in $stats) {

        Write-Host "    Collecting stats for $($stat.name)"
        $jobName = $stat.name
        $customerName = $jobName.split("-")[0]

        if($jobName -notin $report.Keys) {
            $report[$jobName] = @{
                'customer' = $customerName
                'dataInBytes' = $($stat.stats.dataInBytes)
            }
        }
    }
}

### Add headers to export-file
Add-Content -Path $export -Value "Customer, Consumer, Data Size"

### Export data
Write-Host "Exporting data..." -ForegroundColor Yellow

$report.GetEnumerator() | Sort-Object -Property {$_.Name} | ForEach-Object {
    $line = "{0},{1},{2}" -f $_.Value.customer, $_.Name, $_.Value.dataInBytes
    Add-Content -Path $export -Value $line
}
