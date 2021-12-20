### Sample script for finding servers having log4j-core package - Jussi Jaurola <jussi@cohesity.com>

### process commandline arguments
[CmdletBinding()]
param (
    [Parameter(Mandatory = $True)][string]$cohesityCluster, 
    [Parameter(Mandatory = $True)][string]$cohesityUsername,
    [Parameter()][string]$cohesityPassword
    )

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

Find-CohesityFilesForRestore -Search log4j-core | Select-Object Filename,@{Name="Name"; Expression={$_.ProtectionSource.name}}

