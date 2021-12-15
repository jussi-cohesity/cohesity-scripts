### Example script to restore backup new datalock view - Jussi Jaurola <jussi@cohesity.com>

### Note! You need to have cohesity-api.ps1 on same directory and Cohesity PowerShell Module installed

### process commandline arguments
[CmdletBinding()]
param (
    [Parameter(Mandatory = $True)][string]$cluster,    
    [Parameter(Mandatory = $True)][string]$apikey,
    [Parameter(Mandatory = $True)][string]$protectionJob,
    [Parameter()][string]$storageDomain = "DefaultStorageDomain",
    [Parameter(Mandatory = $True)][string]$targetView 
    )

### source the cohesity-api helper code 
. $(Join-Path -Path $PSScriptRoot -ChildPath cohesity-api.ps1)

try {
    apiauth -vip $cluster -useApikey -password $apikey
    Connect-CohesityCluster -Server $cluster -APIKey $apikey
} catch {
    write-host "Cannot connect to cluster $cluster. Please check the apikey!" -ForegroundColor Yellow
    exit
}

### Restore backup to temporary view
$temporaryView = $targetView + "-" + (Get-Random)
Write-Host "Restoring protection group $protectionJob to temporary view $temporaryView"
$restoreTask = Restore-CohesityBackupToView -ProtectionJobName $protectionJob -TargetViewName $temporaryView -QOSPolicy "TestAndDev High"


### Create new datalock view
$storageDomainId = (api get viewBoxes | Where-Object { $_.name  -eq $storageDomain }).id

$newView = @{
    "antivirusScanConfig" = @{
      "isEnabled" = $false;
      "blockAccessOnScanFailure" = $true;
      "scanFilter" = @{
        "isEnabled" = $false;
        "mode" = $null;
        "fileExtensionsList" = @()
      }
    };
    "caseInsensitiveNamesEnabled" = true;
    "category" = "FileServices";
    "enableSmbLeases" = $true;
    "enableSmbOplock" = $true;
    "enableSmbViewDiscovery" = $true;
    "fileExtensionFilter" = @{
      "fileExtensionsList" = @();
      "isEnabled" = $false;
      "mode" = "Blacklist"
    };
    "fileLockConfig" = @{
      "autoLockAfterDurationIdleMsecs" = 900000;
      "defaultRetentionDurationMsecs" = 31536000000;
      "expiryTimestampMsecs" = 0;
      "lockingProtocol" = "SetReadOnly";
      "mode" = "Enterprise"
    };
    "name" = $targetView;
    "overrideGlobalNetgroupWhitelist" = $true;
    "overrideGlobalSubnetWhitelist" = $true;
    "protocolAccess" = @(
      @{
        "type" = "SMB";
        "mode" = "ReadWrite"
      }
    );
    "qos" = @{
      "principalId" = 6;
      "principalName" = "TestAndDev High"
    };
    "securityMode" = "NativeMode";
    "selfServiceSnapshotConfig" = @{
      "enabled" = $false;
      "nfsAccessEnabled" = $false;
      "snapshotDirectoryName" = ".snapshot";
      "smbAccessEnabled" = $false;
      "alternateSnapshotDirectoryName" =  "~snapshot";
      "previousVersionsEnabled" = $true;
      "allowAccessSids" = @(
        "S-1-1-0"
      );
      "denyAccessSids" = @()
    };
    "sharePermissions" = @{
      "permissions" = @(
        @{
          "sid" = "S-1-1-0";
          "access" = "FullControl";
          "mode" = "FolderSubFoldersAndFiles";
          "type" = "Allow"
        }
      );
      "superUserSids" = @() 
    };
    "smbPermissionsInfo" = @{
      "ownerSid" = "S-1-5-32-544";
      "permissions" = @(
        @{
          "sid" = "S-1-1-0";
          "access" = "FullControl";
          "mode" = "FolderSubFoldersAndFiles";
          "type" = "Allow"
        }
      )
    };
    "storageDomainId" = $storageDomainId;
    "storageDomainName" = $storageDomain;
    "storagePolicyOverride" = @{
      "disableInlineDedupAndCompression" = $false
    };
    "subnetWhitelist" = @()
    "viewPinningConfig" = @{
      "enabled" = $false;
      "pinnedTimeSecs" = -1
    };
}


Write-Host "Creating new DataLock view $viewName" 
$view = api post file-services/views $newView -v2

### Clone content

Write-Host "Cloning content of $temporaryView to $targetView"
$cloneContent = @{
   "sourceViewName" = $temporaryView;
   "targetViewName" = $targetView
}

$cloneTask = api post views/overwrite $cloneContent

Write-Host "Adding share and user permissions"
$settings = api put file-services/views/$($view.viewId) $newView -v2

Write-Host "Deleting temporary view $temporaryView" 
$null = api delete "views/$temporaryView"
