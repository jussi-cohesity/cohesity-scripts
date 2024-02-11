### Example script to get storage consumers from cluster - Jussi Jaurola <jussi@cohesity.com>

### Note! You need to have cohesity-api.ps1 on same directory!


### process commandline arguments

[CmdletBinding()]
param (
    [Parameter(Mandatory = $True)][string]$cluster, 
    [Parameter(Mandatory = $True)][string]$username,
    [Parameter()][string]$domain = 'local',
    [Parameter()][ValidateSet('MB','GB','TB')][string]$unit = "TB",
    [Parameter()][int32]$customerPricePerTB = 45,
    [Parameter()][int32]$softwareCostPerTB = 20,
    [Parameter()][int32]$hardwareCostPerTB = 20,
    [Parameter()][float]$resiliencyOverheadMultiplier = 1.5,
    [Parameter()][float]$bufferOverHeadMultiplier = 1.2,
    [Parameter()][string]$export

    )

### source the cohesity-api helper code 
. $(Join-Path -Path $PSScriptRoot -ChildPath cohesity-api.ps1)

try {
    apiauth -vip $cluster -username $username -domain $domain
    $clusterName = (api get cluster).name
} catch {
    write-host "Cannot connect to cluster $cluster" -ForegroundColor Red
    exit
}

### Add headers to export-file
Add-Content -Path $export -Value "Organisation (OrgID), Data Ingested & Retained ($unit), Total Customer Billing, Total Customer Cost, Customer Net Benefit Margin (%), Data Reduction, Storage Consumed for Retained Data ($unit), Storage Consumed with Resiliency ($unit), Storage Consumed with Resiliency and Buffer ($unit)"

### Get usage stats
$units = "1" + $unit
$report = @{}

    $tenants = api get tenants
    Write-Host "    Getting Storage Consumers stats" -ForegroundColor Yellow
    $stats = api get "stats/consumers?maxCount=1000&fetchViewBoxName=true&fetchTenantName=true&fetchProtectionEnvironment=true&consumerType=kProtectionRuns"

    Write-Host "Collecting stats for tenants" -ForegroundColor Yellow

    foreach ($tenant in $tenants) {
        $tenantName = $tenant.name
        $tenantId = $tenant.tenantID

        $dataWrittenBytes = 0
        $dataInBytes = 0

        Write-Host "        Collecting $tenantName stats" -ForegroundColor Yellow
        $tenantStats = $stats.statsList | where { $_.groupList.tenantName -match $tenantName}
        foreach ($tenantStat in $tenantStats) {
            $dataInBytes += $tenantStats.stats.dataInBytes
            $dataWrittenBytes += $tenantStat.stats.dataWrittenBytes
        }

        
         # Export content for tenant
         $dataIngestedAndRetained = [math]::Round(($dataInBytes/$units),1)
         $totalCustomerBilling = ([math]::Round(($dataInBytes/$units),1)) * $customerPricePerTB
         $storageConsumedForRetainedData = ([math]::Round(($dataWrittenBytes/$units),1))
         $storageConsumedWithResiliency = $storageConsumedForRetainedData * $resiliencyOverheadMultiplier
         $storageConsumedWithResiliencyAndBuffer =  $storageConsumedWithResiliency * $bufferOverHeadMultiplier
         $dataReduction = ([math]::Round(($dataInBytes/$units),1)) / ([math]::Round(($dataWrittenBytes/$units),1))
         $totalCustomerCost = ($softwareCostPerTB * $dataIngestedAndRetained) + ($storageConsumedWithResiliencyAndBuffer * $hardwareCostPerTB)
         $customerNetBenefitMargin = ($totalCustomerBilling / $totalCustomerCost) * 100

         $line = "{0},{1},{2},{3},{4},{5},{6}" -f $tenantId, $dataIngestedAndRetained, $totalCustomerBilling, $totalCustomerCost, $customerNetBenefitMargin, $dataReduction, $storageConsumedForRetainedData, $storageConsumedWithResiliency, $storageConsumedWithResiliencyAndBuffer
        
         Add-Content -Path $export -Value $line
    }

