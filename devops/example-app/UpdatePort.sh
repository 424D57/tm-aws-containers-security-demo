#!/bin/bash
PORT=$(kubectl --kubeconfig=kubeconfig get service secjam -o json | jq .spec.ports[0].nodePort)
DSM_URL=https://$(cat DSM_URL)
API_KEY=$(cat api_key)

#curl -k -X GET ${DSM_URL}/api/policies -H “api-version: v1” -H “api-secret-key: ${API_KEY}” > allPolices.json
echo $API_KEY
curl --insecure -X POST ${DSM_URL}/api/policies/search -H "Content-Type: application/json" -H "api-secret-key: ${API_KEY}" -H "api-version: v1" --data '{"searchCriteria":[{"fieldName":"name","stringTest":"equal","stringValue":"EKS-Node-Policy"}]}' > eksPolicy.json


#PolicyID=0
#END=20
#for i in $(seq 1 $END); do
#    NAME=$(cat eksPolicy.json | jq .policies[$i].name)
    #echo ${NAME}
#    ANSWER=“\”EKS-Node-Policy\“”
#    #echo ${ANSWER}
#    if  [[ ${NAME} = ${ANSWER} ]] ; then
        PolicyID=$(cat eksPolicy.json | jq .policies[$i].ID)
#        echo “Updating PoloicyID”
#    fi
#done

echo “Final answer is ${PolicyID}”

curl -k -X GET ${DSM_URL}/api/policies/${PolicyID}/firewall/rules -H "Content-Type: application/json" -H "api-secret-key: ${API_KEY}" -H "api-version: v1" > policyRules.json

#RuleID=$(cat policyRules.json | jq.)

#cat policyRules.json | jq '.firewallRules[] | select(.name == "Block Web Server")'
cat policyRules.json | jq '.firewallRules[] | select(.name == "Block Web Server")' | jq '.destinationPortMultiple[0] = "'${PORT}'"' > newRule.json
NEW_RULE=$(cat newRule.json)
RULE_ID=$(cat newRule.json | jq .ID)
curl -k -X POST ${DSM_URL}/api/policies/${PolicyID}/firewall/rules/${RULE_ID} -H "Content-Type: application/json" -H "api-version: v1" -H "api-secret-key: ${API_KEY}" -d "${NEW_RULE}"