### usage: ./cohesity-tenant-externaltarget-report.ps1 -vip 192.168.1.198 -username admin [ -domain local ] [-days '31'] -export 'filename.csv'

### Sample script to report data transfered to external target per protection job - Jussi Jaurola <jussi@cohesity.com>

### Note! You need to have cohesity-api.ps1 on same directory!
### Requires: Cohesity OS 6.5.1a or later


### process commandline arguments
[CmdletBinding()]
param (
    [Parameter(Mandatory = $True)][string]$vip, 
    [Parameter(Mandatory = $True)][string]$username,
    [Parameter()][string]$domain = 'local',
    [Parameter()][string]$export 
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

if ($export) {
    ### Add headers to export-file
    Add-Content -Path $export -Value "Cluster Name, Organsation Id, Organisation Name, External Target, Protection Group, Storage Consumed (Extneral Target)"
}

### Get mSec time for days 
$date = [DateTime]::Today.AddHours(23).AddMinutes(59).AddSeconds(59)
$endTimeMsecs = [DateTimeOffset]::new($date).ToUnixTimeMilliSeconds()

### Get tentants
Write-Host "Getting tenants..."
$tenants = api get tenants

foreach ($tenant in $tenants) {
    $orgName = $tenant.name
    $orgId = $tenant.tenantId

    Write-Host "Collecting stats for tenant $orgName"

    ## Get CloudArchive stats
    $vaults = api get "vaults?includeMarkedForRemoval=false"
    $orgProtectionGroups = api get "data-protect/protection-groups?tenantIds=$orgId&isDeleted=false&includeTenants=true&includeLastRunInfo=true" -v2
    $orgProtectionGroupsNames =  $orgProtectionGroups.protectionGroups | Select-Object name

    foreach ($vault in $vaults) {
        $vaultOrgConsumed = 0
        $vaultName = $vault.name
        Write-Host "    Collecting tenant $orgname stats for external target $vaultName"
        $vaultStats = api get "reports/dataTransferToVaults?endTimeMsecs=$endTimeMsecs&vaultIds=$($vault.id)"

        ### Loop trough stats and collect tenants protection group stats
        foreach ($job in $orgProtectionGroupsNames) {
            $jobName = $job.name
            $thisJobStats = $vaultstats.dataTransferSummary.dataTransferPerProtectionJob | Where-Object { $_.protectionJobName -eq $job.name }
            $vaultJobConsumed = $($thisjobstats.storageConsumed)

            if ($thisjobstats) {            
                Write-host "        Job $jobName consumed $($thisjobstats.storageConsumed) bytes"

                if ($export) {
                    $line = "{0},{1},{2},{3},{4},{5}" -f $clusterName, $orgId, $orgName, $vaultName, $jobName, $vaultJobConsumed
                    Add-Content -Path $export -Value $line
                }
            }
        }
    }
}
