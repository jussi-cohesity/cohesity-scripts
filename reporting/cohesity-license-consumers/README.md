# Introduction

Example script to pull pay-per-use license consumption per protection group and tenant. Script uses Helios API key for authentication.

## Setup

### Create Helios API Key

Login to Helios, and ensure you have All Clusters selected from top menu. Go to Settings -> Access Management API Keys and click Add API Key. Give key name and store key to safe place. This key is associated to same user used to login to Helios so if you want read only key you need to create Helios-user with RO rights and login as this user before creating a key.

### Download scripts

Run these commands from PowerShell to download the both chargeback script, and api-helper script into your current directory

```powershell
# Download Commands
$apiRepoURL = 'https://raw.githubusercontent.com/bseltz-cohesity/scripts/master/powershell'
$repoURL = 'https://raw.githubusercontent.com/jussi-cohesity/cohesity-scripts/master/reporting/cohesity-license-consumers'
(Invoke-WebRequest -Uri "$repoUrl/cohesity-license-consumers.ps1").content | Out-File "cohesity-license-consumers.ps1"; (Get-Content "cohesity-license-consumers.ps1") | Set-Content "cohesity-license-consumers.ps1"

(Invoke-WebRequest -Uri "$apiRepoUrl/cohesity-api/cohesity-api.ps1").content | Out-File cohesity-api.ps1; (Get-Content cohesity-api.ps1) | Set-Content cohesity-api.ps1
# End Download Commands
```
