### Example script to get FE size for protected objects from past month stats - Jussi Jaurola <jussi@cohesity.com>

### Note! You need to have cohesity-api.ps1 on same directory!


### process commandline arguments
[CmdletBinding()]
param (
    [Parameter(Mandatory = $True)][string]$apikey,
    [Parameter()][ValidateSet('MB','GB','TB')][string]$unit = "GB",
    [Parameter(Mandatory = $true)][string]$export

    )

### source the cohesity-api helper code 
. $(Join-Path -Path $PSScriptRoot -ChildPath cohesity-api.ps1)

try {
    apiauth -helios -password $apikey
} catch {
    write-host "Cannot connect to Helios with key $apikey" -ForegroundColor Yellow
    exit
}

$startTimeUsecs = dateToUsecs (Get-Date -Day 1).Date.AddMonths(-1)
$endTimeUsecs =  dateToUsecs  (Get-Date -Day 1).Date.AddMonths(-1).AddMilliseconds(-1).Date.AddMonths(1)



### Add headers to export-file
Add-Content -Path $export -Value "Customer, Source, Source Size ($unit)"

### Get usage stats
$units = "1" + $unit

$clusters = heliosClusters | Select-Object -Property name
$report = @{}

foreach ($cluster in $clusters.name) {
    ## Conenct to cluster
    Write-Host "Connecting cluster $cluster" -ForegroundColor Yellow
    heliosCluster $cluster
    Write-Host "    Getting Protected Objects" -ForegroundColor Yellow
    $jobs = api get protectionJobs

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
            }     
        }
      
    }

    Write-Host "    Getting Object Stats for VMware Backups" -ForegroundColor Yellow
    foreach ($job in ($jobs | Where { $_.environment -eq 'kVMware'})) {
        $jobName = $job.name
        $customerName = $job.name.split('_')[0]
        Write-Host "    Getting Runs for Job $jobName" -ForegroundColor Yellow
        $run = api get "protectionRuns?jobId=$($job.id)&runTypes=kFull&startTimeUsecs=$($startTimeUsecs)&numRuns=1&excludeNonRestoreableRuns=true"

        if ($run) {
            Write-Host "        Found full backup runs. Collecting stats from it!" -ForegroundColor Yellow
            foreach($source in $run.backupRun.sourceBackupStatus) {
                $sourceName = $source.source.name
                Write-Host "            Collecting stats for $sourceName" -ForegroundColor Yellow
                if($sourceName -notin $report.Keys){
                    $report[$sourcename] = @{}
                    $report[$sourcename]['customerName'] = $customerName
                    $report[$sourcename]['sourceSizeBytes'] = $source.stats.totalBytesReadFromSource
                }
            }
        } else {
            Write-Host "        No full backups found for past month!" -ForegroundColor Yellow
        }
     
    }
}

### Export data
Write-Host "Exporting to $export" -ForegroundColor Yellow
$report.GetEnumerator() | Sort-Object -Property {$_.Name} | ForEach-Object {
    $line = "{0};{1}{2}" -f $_.Value.customerName, $_.Name, [math]::Round($_.Value.sourceSizeBytes/$units,2)
    Add-Content -Path $export -Value $line
}
