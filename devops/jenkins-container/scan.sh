#!/bin/bash
USER=administrator
ECR_BASE=`echo ${ECR_ADDRESS} | cut -d '/' -f 1`
ECR_REPO=`echo ${ECR_ADDRESS} | cut -d '/' -f 2`
NEW_PASSWORD=${SMART_CHECK_PASSWORD}
SMART_CHECK=$(kubectl --kubeconfig=kubeconfig describe services proxy | grep Ingress | cut -d ':' -f 2 | tr -d ' ')
ORIGNAL_PASSWORD=$(kubectl --kubeconfig=kubeconfig get secrets -o jsonpath='{ .data.password }' deepsecurity-smartcheck-auth | base64 --decode)
URL=https://${SMART_CHECK}
CURL=curl
SCANURI=${URL}/api/scans
SESSIONURI=${URL}/api/sessions
CHANGEPASSWORDURI=${URL}/api/
CONTENTTYPE='context type application/json'
PERMITTEDHIGHVULNERABILITIES=10


change_password() {
  currentToken=`cat token`
  temp_id=`cat raw | jq .user.id`
  sed -e 's/^"//' -e 's/"$//' <<< ${temp_id} > id
  ID=`cat id`
  ${CURL} -sk -X POST ${URL}/api/users/${ID}/password -H 'Content-type:application/json' -H 'X-Api-Version:2018-05-01' -H "Authorization: Bearer ${TOKEN}" \
     -d '{"oldpassword":"'${ORIGNAL_PASSWORD}'","newpassword":"'${NEW_PASSWORD}'"}' > raw

}

USER_JSON='{"user": {"userid":\"${USER}\","password":\"${PASSWORD}\"}}'

#echo ${CURL} -k -X POST ${SESSIONURI} -H 'Content-type:application/json' -H 'X-Api-Version:2018-05-01' -d '{"user": {"userid":"'${USER}'","password":"'${PASSWORD}'"}}'
#${CURL} -k -X POST ${SESSIONURI} -H 'Content-type:application/json' -H 'X-Api-Version:2018-05-01' -d '{"user": {"userid":"'${USER}'","password":"'${PASSWORD}'"}}'
#${CURL} -k -X POST ${SESSIONURI} -H 'Content-type:application/json' -H 'X-Api-Version:2018-05-01' -d '{"user": {"userid":"'${USER}'","password":"'${PASSWORD}'"}}' > raw
#LOGIN_RESULT=$( ${CURL} -k -X POST ${SESSIONURI} -H 'Content-type:application/json' -H 'X-Api-Version:2018-05-01' -d '{"user": {"userid":"'${USER}'","password":"'${PASSWORD}'"}}' )
${CURL} -sk -X POST ${SESSIONURI} -H 'Content-type:application/json' -H 'X-Api-Version:2018-05-01' -d '{"user": {"userid":"'${USER}'","password":"'${ORIGNAL_PASSWORD}'"}}'  > raw
cat raw | jq .user.passwordChangeRequired >changepassword 
cat raw | jq .token  > token
#${CURL} -k -X POST ${SESSIONURI} -H 'Content-type:application/json' -H 'X-Api-Version:2018-05-01' -d '{"user": {"userid":"'${USER}'","password":"'${PASSWORD}'"}}' | jq .token  > token || exit -10
TEMP_TOKEN=`cat token`
sed -e 's/^"//' -e 's/"$//' <<< ${TEMP_TOKEN} > token
TOKEN=`cat token`
#echo "My Token is: " ${TOKEN} 
changepassword=`cat changepassword`
if [[ "$changepassword" == "true" ]]; then
        echo "Change passowrd is required"
        change_password
fi

#curl -fsk -X GET ${SCANURI} -H 'Content-type:application/json' -H "Authorization: Bearer ${TOKEN}" || exit -10
if [ -z ${TOKEN} ] ; then 
  ${CURL} -sk -X POST ${SESSIONURI} -H 'Content-type:application/json' -H 'X-Api-Version:2018-05-01' -d '{"user": {"userid":"'${USER}'","password":"'${NEW_PASSWORD}'"}}'  > raw
  cat raw | jq .token  > token
  TEMP_TOKEN=`cat token`
  sed -e 's/^"//' -e 's/"$//' <<< ${TEMP_TOKEN} > token
  TOKEN=`cat token`
  #echo "My Token is: " ${TOKEN} 
fi


${CURL} -sk -X POST ${SCANURI} -H 'Content-type:application/json' -H "Authorization: Bearer ${TOKEN}" \
    -d '{ 
  "id": "", 
  "name": "myScan", 
  "source": { 
    "type": "docker", 
    "registry": "'${ECR_BASE}'", 
    "repository": "'${ECR_REPO}'", 
    "tag": "latest", 
    "credentials": { 
      "token": "", 
      "username": "", 
      "password": "",  
      "aws": { 
        "region": "us-east-1", 
        "accessKeyID": "", 
        "secretAccessKey": "", 
        "role": "", 
        "externalID": "", 
        "roleSessionName": "", 
        "registry": "" 
      } 
    }, 
    "insecureSkipVerify": true, 
    "rootCAs": "" 
  }
} ' | jq .href > href || exit -10


TEMP_HREF=`cat href`
sed -e 's/^"//' -e 's/"$//' <<< ${TEMP_HREF} > href
HREF=`cat href`


${CURL} -sk -X GET ${URL}${HREF} -H 'Content-type:application/json' -H "Authorization: Bearer ${TOKEN}"  > status

TMP=`grep pending status`
while [  -n "$TMP"  ]; do
        sleep 1
        ${CURL} -sk -X GET ${URL}${HREF} -H 'Content-type:application/json' -H "Authorization: Bearer ${TOKEN}" > status
        TMP=`grep pending  status`
done
TMP=`grep progress  status`
while [  -n "$TMP"  ]; do
        sleep 1
        ${CURL} -sk -X GET ${URL}${HREF} -H 'Content-type:application/json' -H "Authorization: Bearer ${TOKEN}" > status
        TMP=`grep progress  status`
done

if [[ $TMP = *"completed-no-findings"* ]]; then
  echo "Smartscan sucessful. No items found."
  exit 0
else
  echo "Smartscan found issue." 
  MALWARESTATUS=`cat status | jq -r '.findings.scanners.malware.status'`
  #if [[ $MALWARESTATUS = "ok" ]]; then
  #  echo "Image is clean of malware"
  #else
  #  echo "Malware found in image"
  #fi  
  ID=$(cat status | jq .id)
  if [ -z "${ID}" ] ; then 
    echo "Unknown ID, please re-run smart check scan. If this continues please contact Trend Micro's Security Jam team. "
    exit -75    
  fi
  MALWARE=`cat status | jq -r .findings.malware`
  if [[ $MALWARE -ne 0 ]] ; then
    echo "Malware detected! Aborting build!"
    cat status | jq '.details.results[]'  | jq 'select(has("malware"))'
    exit -100
  fi
  HIGHVULNERABILITIES=`cat status | jq -r '.findings.vulnerabilities.unresolved.high'`
  #echo "$HIGHVULNERABILITIES high severity vulnerabilities found in image"
  if [[ $HIGHVULNERABILITIES -ne 0 ]]; then
    echo "More detail can be retrieved at the below URLs:"
    VULNERABILITYDETAIL=`cat status | jq -r '.details.results[].vulnerabilities'`
    echo "${VULNERABILITYDETAIL//null/}" | sed '/^\s*$/d'
  fi
  if [[ $HIGHVULNERABLITIES -lt $PERMITTEDHIGHVULNERABILITIES ]]; then
    echo "Number of vulerabilities found is fewer than permitted"
    cat status | jq 
    exit 0
  fi
  echo $TMP
  exit -128
fi

