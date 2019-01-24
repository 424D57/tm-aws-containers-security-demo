#!/bin/bash
DSM_URL=https://$(cat DSM_URL)
API_KEY=$(cat api_key)

NEW_POLICY=$(cat eksPolicy.json)

PolicyID=$(echo $NEW_POLICY | jq .ID)
echo $PolicyID

curl -k -X POST ${DSM_URL}/api/policies/${PolicyID} -H "Content-Type: application/json" -H "api-version: v1" -H "api-secret-key: ${API_KEY}" -d "${NEW_POLICY}"