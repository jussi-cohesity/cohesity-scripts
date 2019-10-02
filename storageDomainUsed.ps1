### usage: ./storageDomainUsed.ps1 -vip 192.168.1.198 -export file.cvs [-username username] [-password password]

### Example script to get billing statistics - Jussi Jaurola <jussi@cohesity.com>
###
### Assumptions:
###
###  - Script uses always previous months statistics
###  - Script looks customer names from StorageDomains and uses these for Protection Jobs also
###

### process commandline arguments
[CmdletBinding()]
param (
    [Parameter(Mandatory = $True)][string]$vip, #cohesity cluster vip
    [Parameter(Mandatory = $True)][string]$export, #cvs-file name
    [Parameter()][string]$username,
    [Parameter()][string]$password
    )
Get-Module -ListAvailable -Name Cohesity* | Import-Module

$secstr = New-Object -TypeName System.Security.SecureString
$password.ToCharArray() | ForEach-Object {$secstr.AppendChar($_)}
$cred = new-object -typename System.Management.Automation.PSCredential -argumentlist $username, $secstr

# Connect to Cohesity cluster
try {
    Connect-CohesityCluster -Server $vip -Credential ($cred)
} catch {
    write-host "Cannot connect to Cohesity cluster $vip" -ForegroundColor Yellow
    exit
}

# Get last months first and last day
$firstDay  = (Get-Date -day 1 -hour 0 -minute 0 -second 0).AddMonths(-1)
$lastDay = (($firstDay).AddMonths(1).AddSeconds(-1))
$startTime = Convert-CohesityDateTimeToUsecs -DateTime $firstDay
$endTime = Convert-CohesityDateTimeToUsecs -DateTime $lastDay


# Write headers to CSV-file 
Add-Content -Path $export -Value "'Customer','Storage domain size (GiB)','Client amount'"

# Get customer-name and storage domain statistics
$stats = Get-CohesityStorageDomain -fetchstats | select-object id,name,stats

Write-Host "Billing statistics for $($lastDay.toString("MMMM yyyy"))" -ForegroundColor Yellow
foreach ($stat in $stats) {

    $virtualNames = @()
    $physicalNames = @()
    $dbNames = @()

    $vmCount = 0
    $physicalCount = 0
    $dbCount = 0

    $separator = "_"
    $customerStorageDomainName = $stat.Name
    $customerNameParts = $($stat.Name).split($separator)
    $customerName = $customerNameParts[1]

    if ($customerName) {
        $customerStorageDomainUsed = ($stat.Stats.UsagePerfStats.totalPhysicalUsageBytes/1GB).Tostring(".00")

        Write-Host "Fetching statistics for customer $customerName ...." -ForegroundColor Yellow

        
        # Fetch VMware/Nutanix/HyperV jobs 
        $jobs = Get-CohesityProtectionJob -Names $customerName | Where-Object Name -cmatch 'ESX|HV|NTNX'
        foreach ($job in $jobs) {
            $runClients = @()
            $maxClients = 0
            $sources = ""

            # Get only runs for last month
            $runs = Get-CohesityProtectionJobRun -JobId $($job.Id) -StartTime $startTime -EndTime $endTime -ExcludeErrorRuns

            # Find run containing max amount of clients for month
            foreach ($run in $runs) {
                $runId = $run.BackupRun.JobRunId
                $runSources = $run.BackupRun.SourceBackupStatus.Source.Name
                $runCount = $runSources.count

                if ($runCount -gt $maxClients) {
                    $runClients += @{$runId = $runCount} 
                    $maxClients = $runCount
                    
                    $runVirtualNames = $runSources
                    $vmCount += $runCount
                }
            }
            $virtualNames = $runVirtualNames
        }

        # Fetch physical jobs with tag
        $jobs = Get-CohesityProtectionJob -Names $customerName | Where-Object Name -cmatch 'WIN|NIX'
        foreach ($job in $jobs) {
            $runClients = @()
            $maxClients = 0
            $sources = ""

            # Get only runs for last month
            $runs = Get-CohesityProtectionJobRun -JobId $($job.Id) -StartTime $startTime -EndTime $endTime -ExcludeErrorRuns

            # Find run containing max amount of clients for month
            foreach ($run in $runs) {
                $runId = $run.BackupRun.JobRunId
                $runSources = $run.BackupRun.SourceBackupStatus.Source.Name
                $runCount = $runSources.count

                if ($runCount -gt $maxClients) {
                    $runClients += @{$runId = $runCount} 
                    $maxClients = $runCount
                    
                    $runPhysicalNames = $runSources
                    $physicalCount += $runCount
                }
            }
            $physicalNames = $runPhysicalNames
        }
        
        $clientAmount = $vmCount + $physicalCount
        # Write statistics to csv file
        $line = "'{0}','{1}','{2}'" -f $customerStorageDomainName, $customerStorageDomainUsed, $clientAmount 
        Add-Content -Path $export -Value $line

        # Export protected sources to file
        $clientListExport = $customerStorageDomainName + "_runclients_" + $($lastDay.toString("MMMM_yyyy")) + ".txt"
        Add-Content -Path $clientListExport -Value "Virtual sources: $virtualNames"
        Add-Content -Path $clientListExport -Value "Physical sources: $physicalNames"
        

        Write-Host "Used capacity is $customerStorageDomainUsed GiB with $clientAmount clients" -ForegroundColor Yellow
    }
}
