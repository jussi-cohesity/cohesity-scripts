### Sample script to resume jobs - Jussi Jaurola <jussi@cohesity.com>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $True)][string]$username,
    [Parameter(Mandatory = $true)][string]$password,
    [Parameter(Mandatory = $true)][string]$cohesityCluster,
    [Parameter()][switch]$runNow
    )

Get-Module -ListAvailable -Name Cohesity* | Import-Module

try {
    Connect-CohesityCluster -Server $cohesityCluster -Credential (New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $username, (ConvertTo-SecureString -AsPlainText $password -Force))
} catch {
    Write-Error "Cannot connect to Cohesity cluster $($cohesityCluster)"
}

### Define jobs to be suspended
$jobArray = "JOBNAME_12months", "JOBNAME_6monts", "JOBNAME_1month"

foreach ($job in $jobArray) {
    Write-Host "Resuming job $job"
    Resume-CohesityProtectionJob -Name $job
    
    if ($runNow) { 
        Start-CohesityProtectionJob -Name $job
    }
}
