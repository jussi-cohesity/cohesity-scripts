# Introduction

`capacityReport.ps1` is a simple script that lists all or specified backupjob runs used capacity (Both frontend and backend) and optionally outputs a csv list with usage details. This data can be used for billing purposes. It is recommended to run the script daily and calculate the monthly average for a more accurate consumption report. 

All units are base 2, so MB is actually MiB etc.

# How to use

```
capacityReport.ps1 
  -vip {ip or name} 
  -username {username} 
  -startDate {mm/dd/yyyy} 
  [ -jobName {search only matching jobs} 
    -runs {number of backupjob runs to list, default 1000} 
    -export {name of csvfile}
    -unit MB|GB|TB (default MB)
    -includeReplicatedJobs true|false, default false ]
```
# Example report

This is an example of CSV output report from script. CSV contains more information than output version due the screen limitations.

```
PS /Users/jpj/cohesity-scripts/capacityReport> Import-Csv ./test.csv | ft  

'Source job' 'Source Size (MB)' 'Backup Size (MB)' 'Frontend Capacity (MB)' 'Backend Capacity (MB)' 'Archived Capacity (MB)' 'Tenant Name'      'Tenant ID' 'Source Cluster'
------------ ------------------ ------------------ ------------------------ ----------------------- ------------------------ -------------      ----------- ----------------
'VMS'        '6144'             '6144'             '6144'                   '11'                    '1280'                   ''                 ''          ''
'Virtual'    '75776'            '77096'            '1320'                   '0'                     '0'                      ''                 ''          'cohesity-01'
'Physical'   '29158'            '307001'           '277843'                 '0'                     '0'                      ''                 ''          'cohesity-01'
'Bizapps'    '3072'             '3072'             '3072'                   '0'                     '0'                      'Organisation Inc' 'org1/'     ''


```

PS C:\Users\Administrator>
# Additional repository

These scripts are using Brian Seltzer's cohesity-api.ps1. You can get it and guide to it from he's repository; https://github.com/bseltz-cohesity/scripts/tree/master/powershell
