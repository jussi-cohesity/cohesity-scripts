### usage: ./restoreSQLdbs.ps1 -vip 192.168.1.198 [-renameprefix "restore-"] [-targetserver servername] [-targetdatadir "D:\datadir"] [-targetlogdir "D:\logdir"] 

### Example script to restore multiple DBs - Jussi Jaurola <jussi@cohesity.com>

### process commandline arguments
[CmdletBinding()]
param (
    [Parameter(Mandatory = $True)][string]$vip, #cohesity cluster vip
    [Parameter()][string]$renameprefix = "", #rename database prefix
    [Parameter()][string]$targetServer, #target server to do restore, default is to original location
    [Parameter()][string]$targetDataDir, #target server to do restore, default is to original location
    [Parameter()][string]$targetLogDir  #target server to do restore, default is to original location

    )
Get-Module -ListAvailable -Name Cohesity* | Import-Module

# Connect to Cohesity cluster
try {
    Connect-CohesityCluster -Server $vip 
} catch {
    write-host "Cannot connect to Cohesity cluster $vip" -ForegroundColor Yellow
    exit
}

if ($targetServer) {
    $targetHost = Get-CohesityProtectionSourceObject -Environments kSql | Where-Object Name -match $targetserver
    $targetHostId = $targetHost.Id
    if (!$targetHost) {
        Write-Host "Cannot find target server $targetserver from registered SQL sources" -ForegroundColor Yellow
        exit
    }
}

# Get DBs to recover

Write-Host "Search by MS SQL Server or Database name" -ForegroundColor Yellow
Write-Host "----------------------------------------" -ForegroundColor Yellow

$restoreTaskContent = @()
Do {
    $searchdb = Read-Host 'Name'
    $searchResults = Find-CohesityObjectsForRestore -Search $searchdb -environments kSql
    $searchResults | Select ObjectName | ForEach-Object  -Begin {$i=0} -Process {"Id $i - $($_.ObjectName)";$i++}
    $id = Read-Host 'Enter ID of DB'
    $selectedDb = $searchResults[$id]
    Write-Host "----------------------------------------" -ForegroundColor Yellow
    $allDone =  Read-Host 'Are all databases selected? (yes/no)'

    $mdfDataPath = $selectedDb.SnapshottedSource.SqlProtectionSource.DbFiles.FullPath[0]
    $mdfDataPath = $mdfDataPath.Substring(0, $mdfDataPath.lastIndexOf('\'))  

    $ldfDataPath = $selectedDb.SnapshottedSource.SqlProtectionSource.DbFiles.FullPath[1]
    $ldfDataPath = $ldfDataPath.Substring(0, $ldfDataPath.lastIndexOf('\'))  

    $dbName = $selectedDb.ObjectName.Split('/')[1]

    $restoreTaskContent += @{
        "dbInstanceName" = $selectedDb.ObjectName;
        "dbName" = $dbName;
        "dbId" = $selectedDb.SnapshottedSource.Id;
        "dbJobId" =  $selectedDb.JobId;
        "dbParentId" =  $selectedDb.SnapshottedSource.SqlProtectionSource.OwnerId;
        "mdfDataPath" = $mdfDataPath;
        "ldfDataPath" = $ldfDataPath;
    }
    
} Until ($allDone -eq "yes")

Write-Host "----------------------------------------" -ForegroundColor Yellow
Write-Host "Recovering $($restoreTaskContent.Count) DBs" -ForegroundColor Yellow

$recoverypoint = Read-Host 'Select wanted recovery point (yyyy-mm-dd hh:mm:ss)'
try {
    $logUsecs = Convert-CohesityDateTimeToUsecs -DateTime $recoverypoint
    $logSecs = [math]::Round($logUsecs/1000000)
} catch {
    write-host "Given recoverypoint is not in valid format (yyyy-mm-dd hh:mm:ss)" -ForegroundColor Yellow
    exit
}

# Restore DBs

foreach ($db in $restoreTaskContent) {
    Write-Host "Creating recovery task for $($db.dbName)" -ForegroundColor Yellow
    $recoveryTask = "Restore-CohesityMSSQLObject -TaskName " + "$($db.dbName)" + "_" + "$(get-date -format yyyy_MM_dd)" 
    $recoveryTask = $recoveryTask + " -SourceId $($db.dbId)"
    $recoveryTask = $recoveryTask + " -HostSourceId $($db.dbParentId)"
    $recoveryTask = $recoveryTask + " -JobId $($db.dbJobId)"
    $recoveryTask = $recoveryTask + " -RestoreTimeSecs $($logSecs)"

    if ($renameprefix) { 
        $newName = $renameprefix + $db.dbName 
        $recoveryTask = $recoveryTask + " -NewDatabaseName $($newName)"
    }

    if ($targetServer) {        
        $recoveryTask = $recoveryTask + " -TargetHostId $($targetHostId)"
    }

    if ($targetDataDir) {
        $recoveryTask = $recoveryTask + " -TargetDataFilesDirectory '$($targetDataDir)'"
    } else {
        $recoveryTask = $recoveryTask + " -TargetDataFilesDirectory '$($db.mdfDataPath)'"
    }

    if ($targetLogDir) {
        $recoveryTask = $recoveryTask + " -TargetLogFilesDirectory '$($targetLogDir)'"
    } else {
        $recoveryTask = $recoveryTask + " -TargetLogFilesDirectory '$($db.ldfDataPath)'"
    }

    # Perform restore for DB
    write-host "$logUsecs"
    write-host "recovery command: $recoveryTask"
    Invoke-Expression $recoveryTask
}

