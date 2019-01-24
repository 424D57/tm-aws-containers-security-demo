#!/bin/bash

## launch a single team for sko 2019

if [ "${1}" == "help" ]
then
    echo -e "Usage: something like below. see script source for detail \n ./launch-env.sh <stackname> <teamname> <passwordForEverything> <dsmUserName> <awsKeyPair> <smartCheckAc> <dsAc> <optionalAwsCliProfile>"
    exit 1
else
    echo -e "\n\n\n\n\n\n building stack with: \n \n passwords=${3} \n teamname=${2} \n sccode=${6} \n dscode=${7} \n keyname=${5} dsmuser=${4} \n\n\n\n\n "
fi

stackname=${1}
teamname=${2}
bastionpassword=${3}
jenkinspassword=${3}
smartcheckpassword=${3}
dsmuser=${4}
keyname=${5}
smartcheckcode=${6}
dscode=${7}
profile=${9:-default}
eventname=demo

if [ -e ~/.aws/config ]
then
echo "Building stack with cli profile"
    aws cloudformation create-stack --debug --disable-rollback \
    --stack-name $1 \
    --capabilities CAPABILITY_IAM \
    --template-url "https://s3-us-west-2.amazonaws.com/tm-aws-containers-security-demo/v1-1/lean-formation.yml" \
    --tags Key=TdcEvent,Value=${eventname} \
    --region us-east-1 \
    --profile ${profile} \
    --parameters \
    ParameterKey=JenkinsPassword,ParameterValue=${jenkinspassword} \
    ParameterKey=BastionPassword,ParameterValue=${bastionpassword} \
    ParameterKey=SmartCheckPassword,ParameterValue=${bastionpassword} \
    ParameterKey=TeamName,ParameterValue=${teamname} \
    ParameterKey=SmartCheckActivationCode,ParameterValue=${smartcheckcode} \
    ParameterKey=DSActivationCode,ParameterValue=${dscode} \
    ParameterKey=KeyName,ParameterValue=${keyname} \
    ParameterKey=EventName,ParameterValue=${eventname} \
    ParameterKey=DevOpsDsmUser,ParameterValue=${dsmuser}

else
echo "Building stack without cli profile"
    aws cloudformation create-stack --debug --disable-rollback \
    --stack-name $1 \
    --capabilities CAPABILITY_IAM \
    --template-url "https://s3-us-west-2.amazonaws.com/tm-aws-containers-security-demo/v1-1/lean-formation.yml" \
    --tags Key=TdcEvent,Value=${eventname} \
    --region us-east-1 \
    --parameters \
    ParameterKey=JenkinsPassword,ParameterValue=${jenkinspassword} \
    ParameterKey=BastionPassword,ParameterValue=${bastionpassword} \
    ParameterKey=SmartCheckPassword,ParameterValue=${bastionpassword} \
    ParameterKey=TeamName,ParameterValue=${teamname} \
    ParameterKey=SmartCheckActivationCode,ParameterValue=${smartcheckcode} \
    ParameterKey=DSActivationCode,ParameterValue=${dscode} \
    ParameterKey=KeyName,ParameterValue=${keyname} \
    ParameterKey=EventName,ParameterValue=${eventname} \
    ParameterKey=DevOpsDsmUser,ParameterValue=${dsmuser}
fi
