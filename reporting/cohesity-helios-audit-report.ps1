### Example script to export official license audit report - Jussi Jaurola <jussi@cohesity.com>

### Note! You need to have cohesity-api.ps1 on same directory! Script exports each clusters audit data to separate file to be sent to Cohesity

### process commandline arguments
[CmdletBinding()]
param (
    [Parameter(Mandatory = $True)][string]$apikey
    )

### source the cohesity-api helper code 
. ./cohesity-api.ps1

try {
    apiauth -helios -password $apikey
} catch {
    write-host "Cannot connect to Helios. Please check the apikey!" -ForegroundColor Yellow
    exit
}

### Get audit report
$clusters = (heliosClusters).name

foreach ($cluster in $clusters) {
    ## Conenct to cluster
    Write-Host "Connecting to cluster $cluster" -ForegroundColor Yellow
    
    heliosCluster $cluster

    Write-Host "    Downloading cluster audit file" -ForegroundColor Yellow

    $auditData = (api get /nexus/license/audit).audit
    $clusterId = (api get cluster | Select id).id
    $time = Get-Date -Format "HH-mm-ss"
    $fileName = "AUDIT-REPORT-" + $clusterId + "-" + $time

    $clusterAuditJson = @{
        "audit" = $auditData;
        "clusterId" = $clusterId;
    }

    $clusterAuditJson | ConvertTo-Json | Out-File $filename
}
