### usage: ./cohesity-reporting-agent-runs.ps1 -vip 192.168.1.198 -username admin [ -domain local ] [-export 'filename.csv']

### Sample script to report physical agent front end capacity - Jussi Jaurola <jussi@cohesity.com>


### process commandline arguments
[CmdletBinding()]
param (
    [Parameter(Mandatory = $True)][string]$vip, 
    [Parameter(Mandatory = $True)][string]$username,
    [Parameter()][string]$domain = 'local',
    [Parameter(Mandatory = $True)][string]$export 
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

$report = @{}

### Get mSec time for days 
$date = [DateTime]::Today.AddHours(23).AddMinutes(59).AddSeconds(59)
$endTimeMsecs = [DateTimeOffset]::new($date).ToUnixTimeMilliSeconds()

Write-Host "Collecting stats for tenants"
$tenants = api get tenants

foreach ($tenant in $tenants) {
    $tenantName = $tenant.name
    $tenantId = $tenant.tenantId
    $tenantId = $tenantId.Substring(0,$tenantId.Length-1)

    Write-Host "    Collecting $tenantName stats"
    
    apiauth -vip $vip -username $username -tenantId $tenantId

    $jobs = api get "data-protect/protection-groups?isDeleted=false&includeTenants=true&includeLastRunInfo=true&environments=kSQL" -v2
    foreach ($job in $jobs.protectionGroups) {
        $jobName = $job.name
        $jobId = $job.id.split(':')[2]
        Write-Host "        Collecting stats for Protection Group $($job.name)"
            $runs = api get protectionRuns?jobId=$($jobId)`&excludeNonRestoreableRuns=true
            foreach ($run in $runs) {
                if ($run.backupRun.snapshotsDeleted -eq $false) {
                    foreach($source in $run.backupRun.sourceBackupStatus) {
                        $sourcename = $source.source.name
                        if($sourcename -notin $report.Keys){
                            $report[$sourcename] = @{}
                            $report[$sourcename]['organisationId'] = $tenantId
                            $report[$sourcename]['organisationName'] = $tenantName
                            $report[$sourcename]['protectionGroup'] = $jobName
                            $report[$sourcename]['size'] = 0
                            $report[$sourcename]['lastBackupTimeStamp'] = usecsToDate ($source.stats.startTimeUsecs)
                            
                        }
                        $report[$sourcename]['size'] += $source.stats.totalBytesReadFromSource
                    }
                }
            }
        
    }
}

### Export data
$exportJsonContent = @()

$report.GetEnumerator() | Sort-Object -Property {$_.Value.organisationName} | ForEach-Object {
    ### Build JSON
    $exportJsonContent += @{
        "timestamp" = $_.Value.lastBackupTimeStamp.ToString();                             
        "resourceId" = $null;               
        "resourceClass" = "AGENT_BASED_BACKUP";
        "FQDN" = $_.Name;
        "resourceName" = $null;
        "customer" = @{
            "customerClass" = "ESC";
            "tenantId" = $_.Value.organisationName;
            "businessGroupId" =  $null;
            "businessGroupName" = $null;
        }
        "resource" = @{
            "lifecycle_state" = "UPDATED";
            "datacenter" =  $null;
            "serviceClass" = $null;
            "datastoreUsage" = @{
                "size" = $_.Value.size;
                "unit" = "GB";
            }
        }
    }
}

$exportJsonContent | ConvertTo-Json -Depth 9 | Set-Content $export
