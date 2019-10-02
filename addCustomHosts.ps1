### usage: ./addCustomHosts.ps1 -vip 192.168.1.198 -username admin [ -domain local ] -hostfile 'hosts.txt'

### Add custom host mappings from file - Jussi Jaurola <jussi@cohesity.com>
###
### NOTE! This replaces _all_ custom host mappings so ensure you have old one's also in hostfile
###
### File content should be csv:
### 
### "IPAddress", "Hostname"
### "10.10.10.10","someserver,someserver.com,host.someserver.com"
### "192.168.12.13","jussi"
###


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

# Get custom hosts from file
try {
    $hosts = Import-Csv $hostfile
} catch {
    write-host "Cannot open hostfile $hostfile" -ForegroundColor Yellow
    exit
}

$hostData = @()
foreach ($mapping in $hosts) 
{
    $domains = @()
    $separator = ","
    $option =  [System.StringSplitOptions]::RemoveEmptyEntries

    foreach ($hname in $mapping.Hostname.Split($separator,$option)) {
        $domains += $hname
    }

    $domainName = $mapping.Hostname
    write-host "Adding custom mapping for $domainName"

    $hostData += @{
        "ip" = $mapping.IPAddress;
        "domainName" = $domains
    }
}

if ($hostData)
{
    $hostsData = @{
        "hosts" = $hostData
    }

    $hostsData | ConvertTo-Json -Depth 3
    api put /nexus/cluster/upload_hosts_file $hostsData
}
