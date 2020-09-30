### usage: ./cohesity-storage-report-tenantstats.ps1 -vip 192.168.1.198 -username admin [ -domain local ] [-days '31'] -export 'filename.csv'

### Capacity reporting example for fetching statistics per organisation - Jussi Jaurola <jussi@cohesity.com

### Note! You need to have cohesity-api.ps1 on same directory!
### Requires: Cohesity OS 6.5.1a or later


### process commandline arguments
[CmdletBinding()]
param (
    [Parameter(Mandatory = $True)][string]$vip, 
    [Parameter(Mandatory = $True)][string]$username,
    [Parameter()][string]$domain = 'local',
    [Parameter()][string]$days = 31,
    [Parameter(Mandatory = $true)][string]$export 
    )

### source the cohesity-api helper code 
. ./cohesity-api.ps1

try {
    apiauth -vip $vip -username $username -domain $domain
    $clusterName = (api get cluster).name
} catch {
    write-host "Cannot connect to cluster $vip" -ForegroundColor Yellow
    exit
}

### Add headers to export-file
Add-Content -Path $export -Value "Cluster Name, Organsation Id, Organisation Name, Data In, Physical Used by Backups,  Storage Consumed in External Target"

### Get mSec time for days 
$date =(Get-Date).AddDays(-$days)
$startTimeMsecs = [DateTimeOffset]::new($date).ToUnixTimeMilliSeconds()

$timeSpan = New-TimeSpan -Days $days
$mSecsBeforeEndTime = $timespan.TotalMilliseconds 

### Get tentants
Write-Host "Getting tenants..."
$tenants = api get tenants

foreach ($tenant in $tenants) {
    $global:orgStorageConsumedInExternalTarget = 0
    $orgName = $tenant.name
    $orgId = $tenant.tenantId
    $orgDataIn = 0
    $orgPhysicalUsedByBackups = 0

    Write-Host "Collecting stats for tenant $orgName"

    ## Get usage stats for past 
    $stat = api get "/reports/tenantStorage?allUnderHierarchy=true&lastNDays=$days&msecsBeforeEndTime=$mSecsBeforeEndTime&reportType=kStorageConsumedByTenantsReport&tenantIds=$orgId&typeAhead=%7B%7D"
   
    ### Go trough all Storage Domains and collect stats
    foreach ($domainStats in $stat.tenantStorageInformation) {
        $orgDataIn += $domainStats.backupDataInBytes
        $orgPhysicalUsedByBackups += $domainStats.backupPhysicalSizeBytes
    }

    ## Get CloudArchive stats
    $vaults = api get "vaults?includeMarkedForRemoval=false"
    $orgProtectionGroups = api get "data-protect/protection-groups?tenantIds=$orgId&isDeleted=false&includeTenants=true&includeLastRunInfo=true" -v2
    $orgProtectionGroupsNames =  $orgProtectionGroups.protectionGroups | Select-Object name

    foreach ($vault in $vaults) {
        $vaultOrgConsumed = 0
        Write-Host "Collecting tenant $orgname stats for external target $($vault.name)"
        $vaultStats = api get "reports/dataTransferToVaults?startTimeMsecs=$startTimeMsecs&vaultIds=$($vault.id)"

        ### Loop trough stats and collect tenants protection group stats
        foreach ($job in $orgProtectionGroupsNames) {
            $thisJobStats = $vaultstats.dataTransferSummary.dataTransferPerProtectionJob | Where-Object { $_.protectionJobName -eq $job.name }
            $vaultOrgConsumed += $($thisjobstats.storageConsumed)

            if ($thisjobstats) {            
                Write-host "Job $($job.name) consumed $($thisjobstats.storageConsumed) bytes"
            }
        }
        if ($vaultOrgConsumed -gt 0) {
            Write-host "Tenant consumed total $vaultOrgConsumed bytes"
            $global:orgStorageConsumedInExternalTarget += $vaultOrgConsumed
        }
    }

    ### write data 
    $line = "{0},{1},{2},{3},{4},{5}" -f $clusterName, $orgId, $orgName, $orgDataIn, $orgPhysicalUsedByBackups, $orgStorageConsumedInExternalTarget
    Add-Content -Path $export -Value $line
}
