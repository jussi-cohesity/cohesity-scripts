### Example script to get storageDomain consumer stats from local clusters - Jussi Jaurola <jussi@cohesity.com

### Note! You need to have cohesity-api.ps1 on same directory!


### process commandline arguments
[CmdletBinding()]
param (
    [Parameter(Mandatory = $True)][string]$vip, 
    [Parameter(Mandatory = $True)][string]$username,
    [Parameter(Mandatory = $True)][string]$storageDomain,
    [Parameter()][ValidateSet('MB','GB','TB')][string]$unit = "GB",
    [Parameter(Mandatory = $true)][string]$export 
    )

### source the cohesity-api helper code 
. ./cohesity-api.ps1

try {
    apiauth -vip $vip -username $username 
    $clusterName = (api get cluster).name
} catch {
    write-host "Cannot connect to cluster $vip" -ForegroundColor Yellow
    exit
}

### Add headers to export-file
Add-Content -Path $export -Value "ProtectionGoup, Data In ($unit), Local Data Written ($unit), Storage Consumed ($unit)"

### Get usage stats
$units = "1" + $unit
$stats = api get "stats/consumers?maxCount=1000&fetchViewBoxName=true&fetchTenantName=true&fetchProtectionEnvironment=true&consumerType=kProtectionRuns"
$storageDomainId = (api get viewBoxes | Where { $_.name -eq $storageDomain } | Select id).id

if ($storageDomainId) {
	foreach ($stat in $stats.statsList | Where { $_.groupList.viewBoxId -eq $storageDomainId }) {
		$jobname = $stat.name
		$dataIn = $stat.stats.dataInBytes/$units
		$localDataWritten = $stat.stats.localDataWrittenBytes/$units
		$storageConsumed = $stat.stats.storageConsumedBytes/$units
		
		### write data 
		$line = "{0},{1},{2},{3}" -f $jobName, $dataIn, $localDataWritten, $storageConsumed
		Add-Content -Path $export -Value $line
	}
} else {
	Write-Host "Cannot find StorageDomain with name $storageDomain. Please check!" -ForegroundColor red
	exit
}
