#!/usr/bin/env python
"""Chargeback Report"""

### This requires pyhesity.py which is available: https://raw.githubusercontent.com/bseltz-cohesity/scripts/master/python/pyhesity.py

### import pyhesity wrapper module
from pyhesity import *
import codecs
import json
from datetime import datetime

### command line arguments
import argparse
parser = argparse.ArgumentParser()
parser.add_argument('-v', '--vip', type=str, required=True)
parser.add_argument('-u', '--username', type=str, required=True)
parser.add_argument('-d', '--domain', type=str, default='local')
parser.add_argument('-f', '--outputfile', type=str, required=True)

args = parser.parse_args()

vip = args.vip
username = args.username
domain = args.domain
outputfile = args.outputfile

# authenticate
apiauth(vip, username, domain)

### Get mSec time for days
nowUsecs = dateToUsecs(datetime.now().strftime("%Y-%m-%d %H:%M:%S"))
endTimeMsecs = (nowUsecs / 1000) + 86399000

print("Collecting stats for tenants")
tenants = api('get', 'tenants')

report = {}

for tenant in sorted(tenants):
    tenantName = tenant['name']
    tenantId = tenant['tenantId'].split('/')[0]
    print('%s' % (tenantName))
    apiauth(vip, username, domain, tenantId=tenantId, quiet=True)
    jobs = api('get', 'data-protect/protection-groups?isDeleted=false&includeTenants=true&includeLastRunInfo=true&environments=kSQL', v=2)

    if jobs['protectionGroups'] is not None:
        for job in jobs['protectionGroups']:
            jobName = job['name']
            jobId = job['id'].split(':')[2]
            print("        Collecting stats for Protection Group %s" % jobName)
            runs = api('get', 'protectionRuns?jobId=%s&excludeNonRestoreableRuns=true' % jobId)
            for run in runs:
                if run['backupRun']['snapshotsDeleted'] is False:
                    for source in run['backupRun']['sourceBackupStatus']:
                        sourcename = source['source']['name']
                        if sourcename not in report:
                            report[sourcename] = {}
                            report[sourcename]['organisationId'] = tenantId
                            report[sourcename]['organisationName'] = tenantName
                            report[sourcename]['protectionGroup'] = jobName
                            report[sourcename]['size'] = 0
                            report[sourcename]['lastBackupTimeStamp'] = usecsToDate(source['stats']['startTimeUsecs'])
                        report[sourcename]['size'] += source['stats'].get('totalBytesReadFromSource',0)

f = codecs.open(outputfile, 'w', 'utf-8')

exportJSONContent = []
for source in report.keys():
    exportJSONContent.append(
        {
            "timestamp": '%s' % report[source]['lastBackupTimeStamp'],
            "resourceId": None,
            "resourceClass": "AGENT_BASED_BACKUP",
            "FQDN": source,
            "resourceName": None,
            "customer": {
                "customerClass": "ESC",
                "tenantId": report[source]['organisationName'],
                "businessGroupId": None,
                "businessGroupName": None
            },
            "resource": {
                "lifecycle_state": "UPDATED",
                "datacenter": None,
                "serviceClass": None,
                "datastoreUsage": {
                    "size": int(round(report[source]['size'] / (1024 * 1024), 2)),
                    "unit": "MiB"
                }
            }
        }
    )
f.write(json.dumps(exportJSONContent, sort_keys=True, indent=4, separators=(', ', ': ')))
f.close()
