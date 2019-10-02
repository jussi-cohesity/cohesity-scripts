### usage: ./getCustomHosts.ps1 -vip 192.168.1.198 -username admin [ -domain local ] -hostfile 'hosts.txt'

### Get custom host mappings from cluster - Jussi Jaurola <jussi@cohesity.com>

### process commandline arguments
[CmdletBinding()]
param (
    [Parameter(Mandatory = $True)][string]$vip,
    [Parameter(Mandatory = $True)][string]$username,
    [Parameter()][string]$domain = 'local',
    [Parameter(Mandatory = $True)][string]$hostfile
)

### source the cohesity-api helper code
. ./cohesity-api

### authenticate
apiauth -vip $vip -username $username -domain $domain

$hostData = api get /nexus/cluster/get_hosts_file 

Add-Content -Path $hostfile -Value '"IPAddress","Hostname"'

foreach ($mapping in $hostData.hosts) 
{
    $ip = $mapping.ip
    $dname = $mapping.domainName -join ','
    $line = '"{0}","{1}"' -f $ip, $dname
    $line
    Add-Content -Path $hostfile -Value $line
}
