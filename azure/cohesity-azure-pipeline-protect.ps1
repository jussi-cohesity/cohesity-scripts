### Sample script for Azure Pipeline Cohesity integration - Jussi Jaurola <jussi@cohesity.com>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $True)][string]$username,
    [Parameter(Mandatory = $true)][string]$password,
    [Parameter(Mandatory = $true)][string]$cohesityCluster,
    [Parameter(Mandatory = $true)][string]$retainDays,
    [Parameter(Mandatory = $true)][string]$application,
    [Parameter(Mandatory = $true)][string]$database 
    )

### Get required module
try {
    Install-Module -Name Cohesity.PowerShell.Core -Scope CurrentUser -Force
} catch {
    Write-Error "Couldn't install Cohesity PowerShell Module"
}

try {
    Connect-CohesityCluster -Server $cohesityCluster -Credential (New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $username, (ConvertTo-SecureString -AsPlainText $password -Force))
} catch {
    Write-Error "Cannot connect to Cohesity cluster $($cohesityCluster)"
}


### Refresh Protection Sources to get new objects
Write-Host "Refreshing Hyper-V sources"
Get-CohesityProtectionSource -Environments KHyperV | ForEach-Object { Update-CohesityProtectionSource -Id $_.protectionSource.Id}

Write-Host "Refreshing MS SQL sources"
Get-CohesityProtectionSource -Environments kSQL | ForEach-Object { Update-CohesityProtectionSource -Id $_.protectionSource.Id}


### Create protection policy for object
$policyName = "pipeline-" + $application + "-" + $database
Write-Host "Creating Protection Policy for application $application"
$policy = New-CohesityProtectionPolicy -PolicyName $policyName -BackupInHours 14 -RetainInDays $retainDays -Confirm:$false

Write-Host "Finding protectionSourceObject for application $application"
$applicationObject = Get-CohesityProtectionSourceObject -Environments KHyperV | Where-Object { $_.name -eq $application } | Select-Object -First 1


### Create job to protect application
Write-Host "Protecting application $application"
$applicationProtectionJob = New-CohesityProtectionJob -Name $application -PolicyName $policyName -SourceIds $($applicationObject.Id) -StorageDomainName 'DefaultStorageDomain' -Environment KHyperV -ParentSourceId $($applicationObject.ParentId)

### Find DB to protect
Write-Host "Finding protectionSourceObject for $database"
$databaseObject = Get-CohesityProtectionSourceObject -Environments kSQL | Where-Object { $_.name -match $database } | Select-Object -First 1

### Create job to protect database
Write-Host "Protecting database $database"
$databaseProtectionJob = New-CohesityProtectionJob -Name $database -PolicyName $policyName -SourceIds $($databaseObject.Id) -StorageDomainName 'DefaultStorageDomain' -Environment kSQL -ParentSourceId $($databaseObject.ParentId)

### Run Protection Jobs
Write-Host "Running protection groups for $application and $database"
Get-CohesityProtectionJob -Names $application | Start-CohesityProtectionJob -RunType KFull
Get-CohesityProtectionJob -Names $database | Start-CohesityProtectionJob -RunType KFull

### Wait until jobs are finished
Start-Sleep 60
$sleepCount = 0

While ($true) {
    $statusApplicationRun = (Get-CohesityProtectionJobRun -JobName $application)[0].backupRun.status
    $statusDatabaseRun = (Get-CohesityProtectionJobRun -JobName $database)[0].backupRun.status

    Write-Host "Current status of application protection group is $statusApplicationRun"
    Write-Host "Current status of application protection group is $statusDatabaseRun"

    if ($statusApplicationRun -eq 'kSuccess') -and ($statusDatabaseRun -eq 'kSuccess'){
        break
    } elseif ($sleepCount -gt '30') {
        Write-Error  "Running protection groups takes too long. Failing!"
    } else {
        Start-Sleep 60
        $sleepCount++
    }
}

Write-Host "Application and Database protection done. Cleaning system"
Remove-CohesityProtectionJob -Id $($applicationProtectionJob.id) -KeepSnapshots -Confirm:$false
Remove-CohesityProtectionJob -Id $($databaseProtectionJob.id) -KeepSnapshots -Confirm:$false
Remove-CohesityProtectionPolicy -Id $($policy.id) -Confirm:$false
