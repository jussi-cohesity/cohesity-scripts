### usage: ./protectionJobStats.ps1 -vip 192.168.1.198 -username admin [-unit MB] [-export stats.csv]

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

if ($export) {
    # Write headers to CSV-file 
    Add-Content -Path $export -Value "'Tenant','Protection Job','Source size ($unit)','Backend size ($unit)'"
}

$jobStats = api get "/reports/backupjobs/storage?allUnderHierarchy=true" 
$units = "1" + $unit

foreach ($stat in $jobStats) {
    $jobName = $stat.backupJobSummary.jobDescription.name
    $jobSourceSize = [math]::Round($stat.backupJobSummary.totalBytesReadFromSource/$units)
    $jobBackendSize = [math]::Round($stat.backupJobSummary.totalPhysicalBackupSizeBytes/$units)
    $tenant = $stat.tenants.name

    Write-Host "Job $jobName source size is $jobSourceSize $unit and they consume $jobBackendSize $unit at cluster" -ForegroundColor Yellow

    if ($export) {
        # Write statistics to csv file
        $line = "'{0}','{1}','{2}','{3}'" -f $tenant, $jobName, $jobSourceSize, $jobBackendSize
        Add-Content -Path $export -Value $line
    }
}
