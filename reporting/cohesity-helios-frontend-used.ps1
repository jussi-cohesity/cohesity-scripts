### Example script to get FE size for protected objects trough Cohesity & VMware - Jussi Jaurola <jussi@cohesity.com>

### Note:
###   You need to have cohesity-api.ps1 on same directory!
###   You need to have VMware PowerCLI installed before using this script
##
## To create encrypted credential file: Get-Credential | Export-Clixml vmware_credentials.xml
##
## vCentersCSV file should look like this:
## vcenter,credentialsfile
## vcenter01,vcenter01-credentials.xml
## vcenter02,vcenter02-credentials.xml


### process commandline arguments
[CmdletBinding()]
param (
    [Parameter(Mandatory = $True)][string]$apikey,
    [Parameter(Mandatory = $True)][string]$vCentersCSV,
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


### Add headers to export-file
Add-Content -Path $export -Value "Customer, Source Name, Source Used ($unit), Source Size ($unit)"

### Get usage stats
$units = "1" + $unit

$clusters = heliosClusters | Select-Object -Property name
$report = @{}
$vmObjects = @{}

### Connect to each vCenter and get list of VMs
$vcenters = Import-Csv ($vCentersCSV)
foreach ($vcenter in $vcenters) {
    try {
        Write-Host "Importing credentials for $($vcenter.vcenter) from file $($vcenter.credentialsfile)" -ForegroundColor Yellow
        $vmwareCredential = Import-Clixml -Path ($vcenter.credentialsfile)

        Write-Host "Connecting to vCenter $($vcenter.vcenter)" -ForegroundColor Yellow
        Connect-VIServer -Server $($vcenter.vcenter) -Credential $vmwareCredential
        Write-Host "Connected to VMware vCenter $($global:DefaultVIServer.Name)" -ForegroundColor Yellow

    } catch {
        write-host "Cannot connect to VMware vCenter $($_.Value.vCenter)" -ForegroundColor Red
        exit
    }
    
    ### Get VM used disk trough vCenter api
    $vms = Get-VM   

    foreach ($vm in $vms) {
        $vmName = $vm.name
        $vmFreeGB = 0
        $vmCapacityGB = 0
        foreach ($disk in $($vm.guest.disks)) {
            $vmFreeGB += $disk.FreeSpaceGB
            $vmCapacityGB += $disk.CapacityGB
        }
        $vmUsedCapacityGB = [math]::Round(($vmCapacityGB - $vmFreeGB), 2) 
        if($vmName -notin $vmObjects.Keys){
            $vmObjects[$vmName] = @{}
            $vmObjects[$vmName]['vmUsedCapacity'] = $vmUsedCapacityGB*1024*1024*1024
        } 
    }    
}

## Collect remaining statistics trough Cohesity Helios
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
    
    foreach ($object in $objects) {
        $sourceName = $object.name
        
        
        $search = (api get "restore/objects?search=$sourceName&environments=kVMware")
      
        if ($search) {
            $customerName  = $search.objectSnapshotInfo.jobName.split('_')
            Write-Host "        Collecting status for object $sourceName" -ForegroundColor Yellow
            $sourceTotalCapacity = 0
            foreach ($vdisk in $sourceFromObjects.vmWareProtectionSource.virtualDisks) {
                $sourceTotalCapacity += $vdisk.logicalSizeBytes
            }
                
            $report[$sourcename] = @{}
            $report[$sourcename]['customerName'] = $customerName
            $report[$sourcename]['sourceSizeBytes'] = $sourceTotalCapacity
            
            ### If there is no VMware response for object zero used bytes value
            if ($vmObjects[$sourcename]['vmUsedCapacity']) {
                $report[$sourcename]['sourceUsedBytes'] = $vmObjects[$sourcename]['vmUsedCapacity']
            } else {
                $report[$sourcename]['sourceUsedBytes'] = 0
            }
        } else {
            Write-Host "        Object $sourceName is not protected. Skipping!" -ForegroundColor Red
        }
    }
}

### Export data
Write-Host "Exporting to $export" -ForegroundColor Yellow
$report.GetEnumerator() | Sort-Object -Property {$_.Name} | ForEach-Object {
    $line = "{0},{1},{2},{3}" -f $_.Value.customerName, $_.Name, [math]::Round($_.Value.sourceUsedBytes/$units,2), [math]::Round($_.Value.sourceSizeBytes/$units,2)
    Add-Content -Path $export -Value $line
}

