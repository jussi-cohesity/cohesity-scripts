### Example script to get storage consumers from helios - Jussi Jaurola <jussi@cohesity.com>

### Note! You need to have cohesity-api.ps1 on same directory!


### process commandline arguments
[CmdletBinding()]
param (
    [Parameter(Mandatory = $True)][string]$apikey,
    [Parameter()][ValidateSet('MB','GB','TB')][string]$unit = "GB",
    [Parameter(Mandatory = $true)][string]$export

    )

### source the cohesity-api helper code 
. $(Join-Path -Path $PSScriptRoot -ChildPath cohesity-api.ps1)

try {
    apiauth -helios -password $apikey
} catch {
    write-host "Cannot connect to Helios with key $apikey" -ForegroundColor Yellow
    exit
}

### Add headers to export-file
Add-Content -Path $export -Value "Cluster Name, Tenant Name, Protection Group, Protection Policy, Environment Type, Source Object Count, Data In ($unit), Data In After Dedupe ($unit), Local Storage Consumed ($unit), Cloud Storage Consumed ($unit), Total Storage Consumed ($unit)"



### Get usage stats
$units = "1" + $unit
$report = @{}
$clusters = heliosClusters | Select-Object -Property name

foreach ($cluster in $clusters.name) {
    ## Connect to cluster
    Write-Host "Connecting cluster $cluster" -ForegroundColor Yellow
    heliosCluster $cluster
    $tenants = api get tenants
    Write-Host "    Getting Storage Consumers stats" -ForegroundColor Yellow
    $stats = api get "stats/consumers?maxCount=1000&fetchViewBoxName=true&fetchTenantName=true&fetchProtectionEnvironment=true&consumerType=kProtectionRuns"

    Write-Host "Collecting stats for tenants" -ForegroundColor Yellow

    foreach ($tenant in $tenants) {
        $tenantName = $tenant.name
        $tenantId = $tenant.tenantId
        $tenantDesc = $tenant.description
        $localUsed = 0
        $cloudUsed = 0
        $logicalUsed = 0

        Write-Host "        Collecting $tenantName stats" -ForegroundColor Yellow
        $tenantStats = $stats.statsList | where { $_.groupList.tenantName -match $tenantName}
        foreach ($tenantStat in $tenantStats) {
            if($tenantName -notin $report.Keys){
                $report[$tenantName] = @{}
                $report[$tenantName]['organisationId'] = $tenantId
                $report[$tenantName]['organisationDesc'] = $tenantDesc
                $report[$tenantName]['dataGenerationDate'] = usecsToDate ($tenantStat.stats.localDataWrittenBytesTimestampUsec)
                
            }
            $report[$tenantName]['localUsed'] += $tenantStat.stats.localDataWrittenBytes
            $report[$tenantName]['cloudUsed'] += $tenantStat.stats.cloudDataWrittenBytes
            $report[$tenantName]['logicalUsed'] += $tenantStat.stats.totalLogicalUsageBytes
        }
    }
}

# Export data
$exportJsonContent = @()
$report.GetEnumerator() | ForEach-Object {
    $organisationId = $_.Value.organisationId
    $organisationName = $_.Name
    $organisationDesc = $_.Value.organisationDesc
    $dataGenerationDate = $_.Value.dataGenerationDate
    $localUsed = [math]::Round(($_.Value.localUsed/$units),1)
    $cloudUsed = [math]::Round(($_.Value.cloudUsed/$units),1)
    $logicalUsed = [math]::Round(($_.Value.logicalUsed/$units),1)

    $exportJsonContent += @{
        $organisationId = @{
            "tenantName" = $organisationName;
            "tenantDescription" = $organisationDesc;
            "tenantStorageUsedOnCohesity" = $localUsed;
            "tenantStorageUsedOnExternal" = $cloudUsed;
            "sourceDataSize" = $logicalUsed;
            "dataGenerationDateAndTime" = $dataGenerationDate;
        }
    }
}

Write-Host "Exporting json to $export"
$exportJsonContent | ConvertTo-Json -Depth 9 | Set-Content $export
