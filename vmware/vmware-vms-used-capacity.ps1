### Example script to list each VMs used capacity in GB - Jussi Jaurola <jussi@cohesity.com>

### Note! You need to have VMware PowerCLI installed before using this script
##
## To create encrypted credential file: Get-Credential | Export-Clixml vmware_credentials.xml


[CmdletBinding()]
param (
    [Parameter(Mandatory = $True, ValueFromPipeline)][string[]]$vcenters,
    [Parameter(Mandatory = $True)][string]$vmwareCred,
    [Parameter(Mandatory = $false)][string]$export
)

Write-Host "Importing credentials from credential file $($vmwareCred)" -ForegroundColor Yellow
Write-Host "Connecting to vCenter(s) [$($vcenters)]" -ForegroundColor Yellow

$vmwareCredential = Import-Clixml -Path ($vmwareCred)
$report = @{}

if ($export) { 
    Add-Content -Path $export -Value "Object, Object Used Capacity (GB)"
}

foreach ($vcenter in $vcenters) {
    try {
        Connect-VIServer -Server $($_.Value.vCenter) -Credential $vmwareCredential
        Write-Host "Connected to VMware vCenter $($global:DefaultVIServer.Name)" -ForegroundColor Yellow
        $connectedVcenter = $_.Value.vCenter
    } catch {
        write-host "Cannot connect to VMware vCenter $($_.Value.vCenter)" -ForegroundColor Yellow
    }

    $vms = Get-VM   

    foreach ($vm in $vms) {
        $vmFreeGB = 0
        $vmCapacityGB = 0
        foreach ($disk in $($vm.guest.disks)) {
            $vmFreeGB += $disk.FreeSpaceGB
            $vmCapacityGB += $disk.CapacityGB
        }
        $vmUsedCapacityGB = [math]::Round(($vmCapacityGB - $vmFreeGB), 2) 
        if($vm -notin $report.Keys){
            $report[$vm] = @{}
            $report[$vm]['vmUsedCapacityGB'] = $vmUsedCapacityGB
        } 
    }

    "`n"
            "Object                          Used Capacity (GB)"
            "------------------              ------------------"
    $report.GetEnumerator() | Sort-Object -Property {$_.Name} | ForEach-Object {
        "{0,25} {1,10}" -f $_.Name,  $_.Value.vmUsedCapacityGB   

        if ($export) { 
            $line = "{0},{1}" -f $_.Name, $_.Value.vmUsedCapacityGB
            Add-Content -Path $export -Value $line
        }
    }
}
