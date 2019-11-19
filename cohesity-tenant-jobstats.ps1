### usage: ./cohesity-tenant-jobstats.ps1 -vip 192.168.1.198 -username admin [-unit MB] [-export stats.csv]

### Example script to get billing statistics per protectionJob - Jussi Jaurola <jussi@cohesity.com>

### Note! You need to have cohesity-api.ps1 on same directory!


### process commandline arguments
[CmdletBinding()]
param (
    [Parameter(Mandatory = $True)][string]$vip, #cohesity cluster vip
    [Parameter(Mandatory = $True)][string]$username,
    [Parameter()][ValidateSet('MB','GB','TB')][string]$unit = "GB",
    [Parameter()][string]$export 
    )

### source the cohesity-api helper code and connect to cluster
try {
    . ./cohesity-api
    apiauth -vip $vip -username $username 
} catch {
    write-host "Cannot connect to cluster $vip" -ForegroundColor Yellow
    exit
}

### cluster Id
$clusterId = (api get cluster).id

if ($export) {
    # Write headers to CSV-file 
    Add-Content -Path $export -Value "'Tenant','Protection Job','Source Logical ($unit)', 'Source Read ($unit)','Source Written ($unit)'"
}

$tenants = api get tenants | Sort-Object -Property name
$jobStats = api get "/reports/backupjobs/storage?allUnderHierarchy=true" 
$units = "1" + $unit

foreach ($tenant in $tenants) {
    $tenantJobStats = $jobStats | Where-Object { $_.tenants.tenantId -eq $tenant.tenantId } 
    $tenantName = $tenant.name
    foreach ($stat in $tenantJobStats) {
        $jobName = $stat.backupJobSummary.jobDescription.name
        $jobSourceSize = [math]::Round($stat.backupJobSummary.totalBytesReadFromSource/$units)
        $jobLogicalSize = [math]::Round($stat.backupJobSummary.totalLogicalBackupSizeBytes/$units)
        $jobBackendSize = [math]::Round($stat.backupJobSummary.totalPhysicalBackupSizeBytes/$units)

        $stat | Select-Object -Property @{Name="Tenant"; Expression={$tenantName}},
                                    @{Name="Protection Job"; Expression={$jobName}},
                                    @{Name="Source Logical ($unit)"; Expression={$jobLogicalSize}},
                                    @{Name="Source Read ($unit)"; Expression={$jobSourceSize}},
                                    @{Name="Source Written ($unit)"; Expression={$jobBackendSize}} 
        if ($export) {
            # Write statistics to csv file
            $line = "'{0}','{1}','{2}','{3}','{4}'" -f $tenantName, $jobName, $jobLogicalSize, $jobSourceSize, $jobBackendSize
            Add-Content -Path $export -Value $line
        }
    }    
}
