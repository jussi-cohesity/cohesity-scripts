### usage: ./registerSQLServers.ps1 -vip 192.168.1.198  -serverlist 'servers.txt'

### Example script to register hosts and sql service from them - Jussi Jaurola <jussi@cohesity.com>

### process commandline arguments
[CmdletBinding()]
param (
    [Parameter(Mandatory = $True)][string]$vip,
    [Parameter(Mandatory = $True)][string]$serverlist
)
Get-Module -ListAvailable -Name Cohesity* | Import-Module

$servers = Get-Content $serverlist

# Connect to Cohesity cluster
try {
    Connect-CohesityCluster -Server $vip 
} catch {
    write-host "Cannot connect to Cohesity cluster $vip" -ForegroundColor Yellow
    exit
}

# Register physical servers
$serverCount = $servers.Count
write-host "Registering $serverCount new sources from $serverlist"

foreach ($server in $servers) 
{
    write-host "Registering host $server as physical host"
    $a = Register-CohesityProtectionSourcePhysical -HostType KWindows -Server $server -PhysicalType KHost
    write-host "Registering SQL server from host $server"
    $serverId = $a.Id
    $newSQL = Register-CohesityProtectionSourceMSSQL -HasPersistentAgent -Id $serverId
}
