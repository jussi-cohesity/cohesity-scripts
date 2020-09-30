### usage: ./cohesity-storage-stats-tenants.ps1 -vip 192.168.1.198 -username admin [ -domain local ] -export 'filename.csv'

### Capacity reporting example for fetching statistics per organisation - Jussi Jaurola <jussi@cohesity.com

### Note! You need to have cohesity-api.ps1 on same directory!
### Requires: Cohesity OS 6.5.1a or later


### process commandline arguments
[CmdletBinding()]
param (
    [Parameter(Mandatory = $True)][string]$vip, 
    [Parameter(Mandatory = $True)][string]$username,
    [Parameter()][string]$domain = 'local',
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
Add-Content -Path $export -Value "Cluster Name, Organsation Id, Organisation Name, Data In, Local Physical Used, External Physical Used, Unique Physical"

### Get tentants
$tenantStats = api get "stats/tenants"

foreach ($tenantStat in $tenantStats.statsList) {
    $orgName = $tenantStat.name
    $orgId = $tenantStat.Id
    $orgDataIn = 0
    $orgPhysicalUsedByBackups = 0

    Write-Host "Collecting stats for tenant $orgName"

    $orgDataIn = $tenantStat.stats.dataInBytes
    $orgLocalPhysicalUsed = $tenantStat.stats.localTotalPhysicalUsageBytes
    $orgCloudPhysicalUsed = $tenantStat.stats.cloudTotalPhysicalUsageBytes
    $orgUniquePhysicalUsed = $tenantStat.stats.uniquePhysicalDataBytes

    
    ### write data 
    $line = "{0},{1},{2},{3},{4},{5},{6}" -f $clusterName, $orgId, $orgName, $orgDataIn, $orgLocalPhysicalUsed, $orgCloudPhysicalUsed, $orgUniquePhysicalUsed
    Add-Content -Path $export -Value $line
}
