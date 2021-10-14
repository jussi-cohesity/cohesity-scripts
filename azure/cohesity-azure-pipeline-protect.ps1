### Sample script for Azure Pipeline Cohesity integration - Jussi Jaurola <jussi@cohesity.com>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $True)][string]$username,
    [Parameter(Mandatory = $true)][string]$password,
    [Parameter(Mandatory = $true)][string]$cohesityCluster,
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

Write-Host "Refreshing Hyper-V sources"
Get-CohesityProtectionSource -Environments KHyperV | ForEach-Object { Update-CohesityProtectionSource -Id $_.protectionSource.Id}

Write-Host "Finding protectionSourceObject for application $application"
$applicationObject = Get-CohesityProtectionSourceObject -Environments KHyperV | Where-Object { $_.name -eq $application } | Select-Object -First 1

Write-Host "Protecting application $application"
New-CohesityProtectionJob -Name $application -PolicyName 'Protect Once' -SourceIds $($applicationObject.Id) -StorageDomainName 'DefaultStorageDomain' -Environment KHyperV -ParentSourceId $($applicationObject.ParentId)
