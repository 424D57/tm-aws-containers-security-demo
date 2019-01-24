#!/bin/bash


DSM_ADMIN=$1
DSM_PASSWORD="Password123!"
CURL=curl

${CURL} -k -X POST https://${DSM_URL}/api/sessions -H 'api-version: v1' -H 'Content-type: application/json' -d '{"userName": "'${DSM_ADMIN}'","password": "'${DSM_PASSWORD}'"}' -c cookie.txt > raw 
#cat raw | jq .RID > RID 
RID=$( cat raw | jq .RID )
sed -e 's/^"//' -e 's/"$//' <<< ${RID} > RID
RID=$( cat RID)
echo ${RID}
 
${CURL} -k -X POST https://${DSM_URL}/api/apikeys -H 'api-version: v1' -H 'Content-type: application/json' -b cookie.txt -H "rID: ${RID}"  -d '{ "keyName": "SecJam 2018 Key", "description": "Created for Security Jam 2018 setup","roleID": 1 }' > api_answer
api_key=$(cat api_answer | jq .secretKey)
sed -e 's/^"//' -e 's/"$//' <<< ${api_key} > api_key
rm raw cookie.txt RID api_answer

API_KEY=$(cat api_key)
${CURL} -k  -X POST https://${DSM_URL}/api/policies/search -H "Content-Type: application/json" -H "api-secret-key: ${API_KEY}" -H "api-version: v1" --data '{"searchCriteria":[{"fieldName":"name","stringTest":"equal","stringValue":"EKS-Node-Policy"}]}' | jq .policies[0] > fullPolicy.json

cat fullPolicy.json | jq 'del(.description,.policySettings,.recommendationScanMode,.autoRequiresUpdate,.interfaceTypes,.SAP)' > eksPolicy.json