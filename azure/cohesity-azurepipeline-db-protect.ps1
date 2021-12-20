### Sample script for Azure Pipeline Cohesity integration to protect MSSQL DB- Jussi Jaurola <jussi@cohesity.com>

$cohesityUsername = "" # Cohesity Cluster Username
$cohesityPassword = "" #Cohesity Cluster Password
$cohesityCluster = "" # Cohesity Cluster to connect
$retainDays = "30" # How long backup is kept

### Get required module

$module = Get-Module -ListAvailable -Name Cohesity* 
if ($module) {
    Get-Module -ListAvailable -Name Cohesity* | Import-Module
} else {
    Install-Module -Name Cohesity.PowerShell.Core -Scope CurrentUser -Force
    Get-Module -ListAvailable -Name Cohesity* | Import-Module
} catch {
    Write-Error "Couldn't install Cohesity PowerShell Module"
}

try {
    Connect-CohesityCluster -Server $cohesityCluster -Credential (New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $cohesityUsername, (ConvertTo-SecureString -AsPlainText $cohesityPassword -Force))
} catch {
    Write-Error "Cannot connect to Cohesity cluster $($cohesityCluster)"
}

Get-CohesityProtectionSource -Environments kSQL | ForEach-Object { Update-CohesityProtectionSource -Id $_.protectionSource.Id}

$databaseName = "$(dbName)"
### Create protection policy for object
$storageDomain = Get-CohesityStorageDomain -Names DefaultStorageDomain

$policyName = "pipeline-" + "$(dbName)"

$policy = New-CohesityProtectionPolicy -PolicyName $policyName -BackupInHours 14 -RetainInDays $retainDays -Confirm:$false

### Find DB to protect
$databaseObject = Get-CohesityProtectionSourceObject -Environments kSQL | Where-Object { $_.name -match $(databaseName) } | Select-Object -First 1

### Create job to protect database
$databaseProtectionJob = New-CohesityProtectionJob -Name $database -PolicyName $policyName -SourceIds $($databaseObject.ParentId) -StorageDomainName 'DefaultStorageDomain' -Environment kSQL -ParentSourceId $($databaseObject.ParentId)

### Run Protection Jobs
Get-CohesityProtectionJob -Names $databaseName | Start-CohesityProtectionJob -RunType KFull

### Wait until jobs are finished
Start-Sleep 60
$sleepCount = 0

While ($true) {
    $statusDatabaseRun = (Get-CohesityProtectionJobRun -JobName $database)[0].backupRun.status

    if ($statusDatabaseRun -eq 'kSuccess'){
        break
    } elseif ($sleepCount -gt '30') {
        Write-Error  "Running protection groups takes too long. Failing!"
    } else {
        Start-Sleep 60
        $sleepCount++
    }
}

### Remove job and policy but keep backups
Remove-CohesityProtectionJob -Id $($databaseProtectionJob.id) -KeepSnapshots -Confirm:$false
Remove-CohesityProtectionPolicy -Id $($policy.id) -Confirm:$false
