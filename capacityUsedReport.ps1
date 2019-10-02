### usage: ./capacityUsedReport.ps1 -vip 192.168.1.198 -export report.txt

### Example script to get billing statistics - Jussi Jaurola <jussi@cohesity.com>
###
### Assumptions:
###
###  - Script uses always previous months statistics
###  - Script looks customer names from StorageDomains and uses these for Protection Jobs also
###

### process commandline arguments
[CmdletBinding()]
param (
    [Parameter(Mandatory = $True)][string]$vip, #cohesity cluster vip
    [Parameter(Mandatory = $True)][string]$export, #cvs-file name
    [Parameter()][string]$username,
    [Parameter()][string]$password,
    [Parameter()][ValidateSet('MB','GB','TB')][string]$unit = "GB"
    )

### source the cohesity-api helper code and connect to cluster
try {
    . ./cohesity-api
    apiauth -vip $vip -username $username 
} catch {
    write-host "Cannot connect to cluster $vip" -ForegroundColor Yellow
    exit
}

$units = "1" + $unit
# Get last months first and last day
$firstDay  = (Get-Date -day 1 -hour 0 -minute 0 -second 0).AddMonths(-1)
$lastDay = (($firstDay).AddMonths(1).AddSeconds(-1))
$startTime = dateToUsecs $firstDay
$endTime = dateToUsecs $lastDay

$stats = api get "viewBoxes?_includeTenantInfo=true&allUnderHierarchy=true&fetchStats=true&includeHidden=false" | select-object id,name,stats
foreach ($stat in $stats) {
    $customerName = $stat.name
    $customerStorageDomainUsed = ($stat.stats.usagePerfStats.totalPhysicalUsageBytes/$units).Tostring(".00")

    Write-Host "Fetching statistics for customer $customerName ...." -ForegroundColor Yellow

    Add-Content -Path $export -Value "Customer: $customerName"
    Add-Content -Path $export -Value "Storage domain size ($unit): $customerStorageDomainUsed"

    $storageDomainStats = api get /reports/objects/storage?msecsBeforeEndTime=2592000000`&viewBoxIds=$($stat.id)

    foreach ($client in $storageDomainStats) {
        $clientName = $client.entity.displayName
        $physicalUsed = ($client.physicalSizeBytesOnPrimary/$units).Tostring(".00")
        $clientEntityType = $client.entity.type
        $dataPoints = $client.dataPoints.snapshotTimeUsecs

        if ($dataPoints) {
            $clientLastBackup = usecsToDate $dataPoints[-1]
            $clientLastBackupDate = $clientLastBackup.toString("MMMM dd yyyy hh:mm:ss")
        } else {
            $clientLastBackupDate = "N/A"
        }
        
        if ($clientEntityType -eq "1") { $clientType = "V" }
        if ($clientEntityType -eq "6") { $clientType = "P" }

        Add-Content -Path $export -Value "Client $clientName, $physicalUsed, $clientLastBackupDate, $clientType"
    }

    Add-Content -Path $export -Value "-----------------------------------------------------"
}
