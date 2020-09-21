# Introduction

Few example scripts to pull chargeback metrics from both Helios and local cluster. Helios version uses Helios API authentication and local version expects same username and password for each clusters listed in clusterlist.

All units are base 2 bytes

All scripts have mandatory export parameter which defines name of csv file used for reporting

## Download the script

Run these commands from PowerShell to download the script(s) into your current directory

```powershell
# Download Commands
$apiRepoURL = 'https://raw.githubusercontent.com/bseltz-cohesity/scripts/master/powershell'
$repoURL = 'https://raw.github.com/jussi-cohesity/cohesity-scripts/tree/master/reporting'
(Invoke-WebRequest -Uri "$repoUrl/cohesity-storage-consumers-report.ps1").content | Out-File "cohesity-storage-consumers-report.ps1"; (Get-Content "cohesity-storage-consumers-report.ps1") | Set-Content "cohesity-storage-consumers-report.ps1"
(Invoke-WebRequest -Uri "$repoUrl/cohesity-storage-report-helios.ps1").content | Out-File "cohesity-storage-report-helios.ps1"; (Get-Content "cohesity-storage-report-helios.ps1") | Set-Content "cohesity-storage-report-helios.ps1"
(Invoke-WebRequest -Uri "$repoUrl/cohesity-storage-report-local.ps1").content | Out-File "cohesity-storage-report-local.ps1"; (Get-Content "cohesity-storage-report-local.ps1") | Set-Content "cohesity-storage-report-local.ps1"
(Invoke-WebRequest -Uri "$repoUrl/cohesity-storage-report-tenantstats.ps1").content | Out-File "cohesity-storage-report-tenantstats.ps1"; (Get-Content "cohesity-storage-report-tenantstats.ps1") | Set-Content "cohesity-storage-report-tenantstats.ps1"


(Invoke-WebRequest -Uri "$apiRepoUrl/cohesity-api/cohesity-api.ps1").content | Out-File cohesity-api.ps1; (Get-Content cohesity-api.ps1) | Set-Content cohesity-api.ps1
# End Download Commands
```

# Additional repository

These scripts are using Brian Seltzer's cohesity-api.ps1. You can get it and guide to it from he's repository; https://github.com/bseltz-cohesity/scripts/tree/master/powershell
