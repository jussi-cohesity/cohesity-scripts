### Example script to get FE size for protected objects trough Cohesity & VMware - Jussi Jaurola <jussi@cohesity.com>

### Note:
###   You need to have cohesity-api.ps1 on same directory!
###   You need to have VMware PowerCLI installed before using this script
##
## To create encrypted credential file: Get-Credential | Export-Clixml vmware_credentials.xml



### process commandline arguments
[CmdletBinding()]
param (
    [Parameter(Mandatory = $True)][string]$apikey,
    [Parameter(Mandatory = $True)][string]$vcenter,
    [Parameter(Mandatory = $True)][string]$vmwareCred,
    [Parameter()][ValidateSet('MB','GB','TB')][string]$unit = "GB",
    [Parameter(Mandatory = $true)][string]$export
    )

### source the cohesity-api helper code 
. $(Join-Path -Path $PSScriptRoot -ChildPath cohesity-api.ps1)


### Connect to Cohesity Helios
try {
    Write-Host "Connecting to Helios" -ForegroundColor Yellow
    apiauth -helios -password $apikey
} catch {
    write-host "Cannot connect to Helios with key $apikey" -ForegroundColor Red
    exit
}

### Connect to vCenter
try {
    Write-Host "Importing credentials from credential file $($vmwareCred)" -ForegroundColor Yellow
    $vmwareCredential = Import-Clixml -Path ($vmwareCred)

    Write-Host "Connecting to vCenter $($vcenter)" -ForegroundColor Yellow
    Connect-VIServer -Server $($vCenter) -Credential $vmwareCredential
    Write-Host "Connected to VMware vCenter $($global:DefaultVIServer.Name)" -ForegroundColor Yellow

    apiauth -helios -password $apikey
} catch {
    write-host "Cannot connect to VMware vCenter $($_.Value.vCenter)" -ForegroundColor Red
    exit
}

$startTimeUsecs = dateToUsecs (Get-Date -Day 1).Date.AddMonths(-1)
$endTimeUsecs =  dateToUsecs  (Get-Date -Day 1).Date.AddMonths(-1).AddMilliseconds(-1).Date.AddMonths(1)


### Add headers to export-file
Add-Content -Path $export -Value "Customer, Source Name, Source Used ($unit), Source Size ($unit)"

### Get usage stats
$units = "1" + $unit

$clusters = heliosClusters | Select-Object -Property name
$report = @{}
$vmObjects = @{}

### Get VM used disk trough vCenter api
$vms = Get-VM   

foreach ($vm in $vms) {
    $vmFreeGB = 0
    $vmCapacityGB = 0
    foreach ($disk in $($vm.guest.disks)) {
        $vmFreeGB += $disk.FreeSpaceGB
        $vmCapacityGB += $disk.CapacityGB
    }
    $vmUsedCapacityGB = [math]::Round(($vmCapacityGB - $vmFreeGB), 2) 
    if($vm -notin $vmObjects.Keys){
        $vmObjects[$vm] = @{}
        $vmObjects[$vm]['vmUsedCapacity'] = $vmUsedCapacityGB*1024*1024*1024
    } 
}

foreach ($cluster in $clusters.name) {
    ## Conenct to cluster
    Write-Host "Connecting cluster $cluster" -ForegroundColor Yellow
    heliosCluster $cluster
    Write-Host "    Getting Protected Objects" -ForegroundColor Yellow
    $objects = api get protectionSources/objects | Where { $_.environment -eq 'kVMware'} 

    Write-Host "    Getting Object Stats for Physical Backups" -ForegroundColor Yellow
    foreach ($object in ((api get "protectionSources/registrationInfo?useCachedData=true&pruneNonCriticalInfo=true&includeEntityPermissionInfo=true&includeApplicationsTreeInfo=true&allUnderHierarchy=true").rootNodes | Where { $_.rootNode.environment -eq 'kPhysical' })) {
        if ($object.stats.protectedSize) {
            $sourceSizeBytes = 0
            $sourceName = $object.rootNode.name
            Write-Host "        Getting Stats for $sourceName" -ForegroundColor Yellow

            foreach ($stat in $object.statsByEnv) {
                $sourceSizeBytes += $stat.protectedSize
            }   

            $customerName = (api get "data-protect/search/objects?searchString=$($sourceName)&includeTenants=true&count=5" -v2).objects.objectProtectionInfos.protectionGroups.name.split('_')[0] | Select-Object -First 1
            if($sourceName -notin $report.Keys){
                $report[$sourcename] = @{}
                $report[$sourcename]['customerName'] = $customerName
                $report[$sourcename]['sourceSizeBytes'] = $sourceSizeBytes
                $report[$sourcename]['sourceUsedBytes'] = $sourceSizeBytes
            }     
        }
      
    }

    Write-Host "    Getting Object Stats for VMware Backups" -ForegroundColor Yellow
    $objects = api get protectionSources/objects | Where { $_.environment -eq 'kVMware'}


    $jobs = api get "data-protect/protection-groups?isDeleted=false&includeTenants=true&includeLastRunInfo=true&environments=kVMware" -v2

    foreach ($job in $jobs.protectionGroups) {
        $jobName = $job.name
        $jobId = $job.id.split(':')[2]
        $customerName = $job.name.split('_')[0]
        Write-Host "        Collecting stats for object from Protection Group $($job.name)" -ForegroundColor Yellow
        $runs = api get protectionRuns?jobId=$($jobId)`&excludeNonRestoreableRuns=false
        foreach ($run in $runs) {        
            foreach($source in $run.backupRun.sourceBackupStatus) {

                ### Get source size
                $sourceFromObjects = $objects | Where { $_.name -eq $source}
                $sourceTotalCapacity = 0

                foreach ($vdisk in $sourceFromObjects.vmWareProtectionSource.virtualDisks) {
                    $sourceTotalCapacity += $vdisk.logicalSizeBytes
                }

                $sourcename = $source.source.name
                if($sourcename -in $report.Keys) {
                    $report[$sourcename]['customerName'] = $customerName
                    $report[$sourcename]['sourceSizeBytes'] = $sourceTotalCapacity
                    $report[$sourcename]['sourceUsedBytes'] = $vmObjects[$sourcename]['vmUsedCapacity']
                }
            }
        }       
    }
}

### Export data
Write-Host "Exporting to $export" -ForegroundColor Yellow
$report.GetEnumerator() | Sort-Object -Property {$_.Name} | ForEach-Object {
    $line = "{0},{1},{2},{3}" -f $_.Value.customerName, $_.Name, [[math]::Round($_.Value.sourceUsedBytes/$units,2), math]::Round($_.Value.sourceSizeBytes/$units,2)
    Add-Content -Path $export -Value $line
}

