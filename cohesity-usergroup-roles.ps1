### Example script to export all cluster users/groups with their mapped roles - Jussi Jaurola <jussi@cohesity.com>

### process commandline arguments
[CmdletBinding()]
param (
    [Parameter(Mandatory = $True)][string]$cluster, #cohesity cluster vip
    [Parameter()][string]$export #If not given just output to terminal
    )

# Check if Cohesity PowerShell is installed, and if not install it

if (!(Get-Module -ListAvailable -Name "Cohesity.PowerShell.Core")) {
    Write-Host "Installing Cohesity PowerShell Module" -ForegroundColor Yellow
    Install-Module Cohesity.PowerShell.Core -Scope CurrentUser -Force
}

# Connect to Cohesity cluster
try {
    Connect-CohesityCluster -Server $cluster 
} catch {
    write-host "Cannot connect to Cohesity cluster $cluster" -ForegroundColor Yellow
    exit
}
if ($export) {
    Add-Content -Path $export -Value "Name, Type, Roles"
}
$mappings = @{}

Write-Host "Getting all users and their roles" -ForegroundColor Yellow
$users = Get-CohesityUser | Select-Object Username, Roles 

foreach ($user in $users) {
    $key = $user.Username
    if ($user.Roles) {
        if($key -notin $mappings.Keys){
            $mappings[$key] = @{}
            $mappings[$key]['type'] = "User"
            $mappings[$key]['roles'] = ""       
        }
        foreach ($role in $user.roles) {
            $mappings[$key]['roles'] += $role + " "
        }
    } 
}

Write-Host "Getting all groups and their roles" -ForegroundColor Yellow
$groups = Get-CohesityUserGroup | Select-Object Name, Roles

foreach ($group in $groups) {
    $key = $group.name
    if ($group.Roles) {
        if($key -notin $mappings.Keys){
            $mappings[$key] = @{}
            $mappings[$key]['type'] = "Group"
            $mappings[$key]['roles'] = ""       
        }
        foreach ($role in $group.roles) {
            $mappings[$key]['roles'] += $role + " "
        }
    }
}

Write-Host "-------------" -ForegroundColor Yellow

$mappings.GetEnumerator() | Sort-Object -Property {$_.Name} | ForEach-Object {
    if ($_.Value.Roles) {
        Write-Host "$($_.Name) has roles $($_.Value.roles)" -ForegroundColor Yellow
        if ($export) {
            $line = "{0},{1},{2}" -f $_.Name, $_.Value.type, $_.Value.Roles
            Add-Content -Path $export -Value $line
        }
    }
}

