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

### Remove old export-file if exists
if (Test-Path $export) { 
    Remove-Item $export 
}

### Add headers to export-file
Add-Content -Path $export -Value "Organisation (OrgID); Organisation Name; Data Ingested & Retained ($unit); Total Customer Billing; Total Customer Cost; Customer Net Benefit Margin (%); Data Reduction; Storage Consumed for Retained Data ($unit); Storage Consumed with Resiliency ($unit); Storage Consumed with Resiliency and Buffer ($unit)"

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
        if ($tenantStats) {
            foreach ($tenantStat in $tenantStats) {
                if ($tenantStat.stats.dataInBytes) {
                    $dataInBytes += $tenantStat.stats.dataInBytes
                }
                if ($tenantStat.stats.dataWrittenBytes) {
                    $dataWrittenBytes += $tenantStat.stats.dataWrittenBytes
                }
            }

            if ($dataInBytes -gt 0) {
        
                 # Export content for tenant
                 $dataIngestedAndRetained = [math]::Round(($dataInBytes/$units),1)
                 $totalCustomerBilling = [math]::Round(($dataIngestedAndRetained * $customerPricePerTB),1)
                 $storageConsumedForRetainedData = ([math]::Round(($dataWrittenBytes/$units),1))
                 $storageConsumedWithResiliency = ([math]::Round(($storageConsumedForRetainedData * $resiliencyOverheadMultiplier),1))
                 $storageConsumedWithResiliencyAndBuffer =  ([math]::Round(($storageConsumedWithResiliency * $bufferOverHeadMultiplier),1))
                 $dataReduction = [math]::Round(($dataInBytes/$dataWrittenBytes),1)
                 $totalCustomerCost = ([math]::Round((($softwareCostPerTB * $dataIngestedAndRetained) + ($storageConsumedWithResiliencyAndBuffer * $hardwareCostPerTB)),1))
                 $customerNetBenefitMargin = ([math]::Round(((($totalCustomerBilling / $totalCustomerCost) * 100)),1))

                 $line = "{0};{1};{2};{3};{4};{5};{6};{7};{8};{9}" -f $tenantId, $tenantName, $dataIngestedAndRetained, $totalCustomerBilling, $totalCustomerCost, $customerNetBenefitMargin, $dataReduction, $storageConsumedForRetainedData, $storageConsumedWithResiliency, $storageConsumedWithResiliencyAndBuffer
        
                 Add-Content -Path $export -Value $line
            } else {
                Write-Host "            DataIN found for $tenantName is zero" -ForegroundColor Yellow
            }
        } else {
            Write-Host "            No stats found for $tenantName" -ForegroundColor Yellow
        }
    }
