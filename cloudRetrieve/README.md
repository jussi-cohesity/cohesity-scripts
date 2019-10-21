# Introduction

`cloudRetrieve.ps1` is a simple script to automate CloudRetrieve search, and if defined it will automatically retrieve latest snapshot data from external target also.

# How to use

```
cloudRetrieve.ps1 
  -vip {ip or name} 
  -username {username} 
  [ -domain local ]
  -externalTarget targetname 
  -startDate 'mm/dd/yyyy' 
  -endDate 'mm/dd/yyyy' 
  [-retrieve true|false, default false] 
  [-storageDomain 'domainanme'] 
  [-jobNames job1,job2,job3]
```


These scripts are using Brian Seltzer's cohesity-api.ps1. You can get it and guide to it from he's repository; https://github.com/bseltz-cohesity/scripts/tree/master/powershell
