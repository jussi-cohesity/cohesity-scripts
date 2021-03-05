
### Sample script for billign automation using webhooks - Jussi Jaurola <jussi@cohesity.com>


### process commandline arguments
[CmdletBinding()]
param (
    [Parameter(Mandatory = $True)][string]$username,
    [Parameter()][string]$domain = 'local',
    [Parameter(Mandatory = $True)][string]$export.
    [object] $webHookData
    )

### Get mSec time for days 
$date = [DateTime]::Today.AddHours(23).AddMinutes(59).AddSeconds(59)
$endTimeMsecs = [DateTimeOffset]::new($date).ToUnixTimeMilliSeconds()
$report = @{}


if ($webHookData) {
    ### source the cohesity-api helper code 
    . ./cohesity-api.ps1

    $webHookData = (ConvertFrom-Json -InputObject $webHookData)

    # get source cluster from webhook data

    $vip = $webHookData.alertProperties.run_url.split('/')[2]


    # connect to cluster
    try {
        apiauth -vip $vip -username $username -domain $domain
        $clusterName = (api get cluster).name
    } catch {
        write-host "Cannot connect to cluster $vip" -ForegroundColor Yellow
        exit
    }

    $cluster = api get cluster
    $clusterId = $cluster.id
    $incarnationId = $cluster.incarnationId

    # get protectionJob run details
    $jobId = $webHookData.alertProperties.job_id
    $runId = $webHookData.alertProperties.run_url.split('/')[8]

    Write-Host "Collecting stats for job's $jobId run $runId"
  
    $run = api get "data-protect/protection-groups/$clusterId`:$incarnatiomnId`:$jobId/runs/$jobId`:$runId`?includeObjectDetails=true" -v2

    $tenantName = $run.permissions.name
    
    foreach($source in $run.objects) {
        $sourcename = $source.object.name
        if($sourcename -notin $report.Keys) {
            $report[$sourcename] = @{}
            $report[$sourcename]['organisationId'] = $tenantId
            $report[$sourcename]['organisationName'] = $tenantName
            $report[$sourcename]['size'] = 0
            $report[$sourcename]['lastBackupTimeStamp'] = usecsToDate ($source.localSnapshotInfo.snapshotInfo.startTimeUsecs)
        }
        $report[$sourcename]['size'] += [math]::Round($source.localSnapshotInfo.snapshotInfo.stats.bytesRead/1GB)
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
}
