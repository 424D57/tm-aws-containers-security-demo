#!/bin/bash

##
##  Build Jenkins server
##

ACTIVATIONURL="dsm://${DSM_URL}:4120/"
MANAGERURL="https://${DSM_URL}:443"
CURLOPTIONS='--silent --tlsv1.2'
linuxPlatform='';
isRPM='';
EKS_STACK_NAME="${EKS_CLUSTER_NAME}-stack"
BASES3="https://${BUCKET_NAME}.s3.amazonaws.com/${BUCKET_PREFIX}"

#Update it
yum -y update

# Install Docker
yum -y update && yum -y install python-pip jq git
pip install --upgrade pip &> /dev/null
yes | sudo amazon-linux-extras install docker
usermod -a -G docker ec2-user
service docker start

# Install docker-compose
curl -L https://github.com/docker/compose/releases/download/1.23.1/docker-compose-`uname -s`-`uname -m` -o /usr/bin/docker-compose
chmod +x /usr/bin/docker-compose

## Install kubectl
curl -LO https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl
chmod +x ./kubectl
mv ./kubectl /bin/.

## Install aws-iam-authenticator
curl -o aws-iam-authenticator https://amazon-eks.s3-us-west-2.amazonaws.com/1.10.3/2018-07-26/bin/linux/amd64/aws-iam-authenticator
chmod +x ./aws-iam-authenticator
mv ./aws-iam-authenticator /bin/.

## Weird, but... force update aws cli
rm -f /bin/aws
yum install -y python-pip
pip install awscli --upgrade

# Creating the new user
echo ${BASTION_PASSWORD} | passwd --stdin ec2-user

# Enabling password SSH
sed -i '/PasswordAuthentication no/s/^/#/g' /etc/ssh/sshd_config
sed -i '/PasswordAuthentication yes/s/^#//g' /etc/ssh/sshd_config
service sshd restart

# Configure Git client
yum install git -y
sudo -Eu ec2-user bash -c 'git config --global credential.helper '"'"'!aws codecommit credential-helper $@'"'"
sudo -Eu ec2-user bash -c "git config --global credential.UseHttpPath true"
mkdir /home/ec2-user/repository
chown -R ec2-user:ec2-user /home/ec2-user/repository
echo "BEGIN git clone ${GITURL}"
sudo -Eu ec2-user bash -c "git clone ${GITURL} /home/ec2-user/repository"
echo "END git clone ${GITURL} "

# Configuring the docker client to use the right access to ECR
$(aws ecr get-login --no-include-email --region us-east-1)
docker pull ubuntu:latest
docker tag ubuntu:latest ${ECR_ADDRESS}:latest
docker push ${ECR_ADDRESS}:latest

## Configuting AWS Region
export AWS_REGION=$(curl -s 169.254.169.254/latest/dynamic/instance-identity/document | jq -r .region)
echo "export AWS_REGION=${AWS_REGION}" >> ~/.bash_profile
aws configure set default.region ${AWS_REGION}
aws configure get default.region

## Creating EKS Cluster
aws cloudformation create-stack \
  --stack-name ${EKS_STACK_NAME} \
  --template-url ${BASES3}eks-helpers/eks-formation.yml \
  --tags Key=TdcEvent,Value=${EVENT_NAME} \
  --parameters \
    ParameterKey=KeyName,ParameterValue=${KEY_NAME} \
    ParameterKey=VPC,ParameterValue=${VPC_ID} \
    ParameterKey=PublicSubnet1,ParameterValue=${SUBNET_1} \
    ParameterKey=PublicSubnet2,ParameterValue=${SUBNET_2}  \
    ParameterKey=NodeInstanceType,ParameterValue=${NODE_INSTANCE_TYPE} \
    ParameterKey=DsmDns,ParameterValue=${DSM_URL} \
    ParameterKey=BaseS3,ParameterValue=${BASES3} \
    ParameterKey=TeamName,ParameterValue=${TEAM_NAME} \
    ParameterKey=EventName,ParameterValue=${EVENT_NAME} \
    ParameterKey=BaseS3,ParameterValue=${BASES3} \
    --capabilities CAPABILITY_IAM

## Waiting for the EKS Cluster to become active
OUTPUT=`aws cloudformation describe-stacks --stack-name ${EKS_STACK_NAME} --query 'Stacks[0].StackStatus' --output text`;
while [[ ${OUTPUT} != CREATE_COMPLETE ]]
do
  OUTPUT=`aws cloudformation describe-stacks --stack-name ${EKS_STACK_NAME} --query 'Stacks[0].StackStatus' --output text`;
  sleep 5
done


while [ ! -f /root/.kube/config ]
do
  ## Get the cluster name and node Role ARN
  export CLUSTER_NAME=`aws cloudformation describe-stacks --stack-name ${EKS_STACK_NAME} --query 'Stacks[0].Outputs[?OutputKey==\`ClusterName\`].OutputValue' --output text`
  export NODE_ROLE_ARN=`aws cloudformation describe-stacks --stack-name ${EKS_STACK_NAME} --query 'Stacks[0].Outputs[?OutputKey==\`NodeInstanceRole\`].OutputValue' --output text`


  ## Configure kubectl
  aws eks update-kubeconfig --name ${CLUSTER_NAME}
  export KUBECONFIG=/root/.kube/config
done

## Making nodes available to EKS
yum install -y gettext
aws s3 cp s3://${BUCKET_NAME}/${BUCKET_PREFIX}eks-helpers/aws-auth-cm.yaml aws-auth-cm.yaml
envsubst < aws-auth-cm.yaml > temp | mv -f temp aws-auth-cm.yaml
kubectl --kubeconfig /root/.kube/config apply -f aws-auth-cm.yaml

## Waiting for nodes to become available to the master
OUTPUT=`kubectl --kubeconfig /root/.kube/config get nodes`;
while [[ ${OUTPUT} = 'No resources found.' ]]
do
  OUTPUT=`kubectl --kubeconfig /root/.kube/config get nodes`;
  sleep 5
done

## Making a persistent storage available
aws s3 cp s3://${BUCKET_NAME}/${BUCKET_PREFIX}eks-helpers/storageclass.yml storageclass.yml
kubectl --kubeconfig /root/.kube/config create -f storageclass.yml
kubectl --kubeconfig /root/.kube/config get storageclass
kubectl --kubeconfig /root/.kube/config patch storageclass gp2 -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

## Installing helm
curl https://raw.githubusercontent.com/kubernetes/helm/master/scripts/get > get_helm.sh
chmod 700 get_helm.sh
./get_helm.sh
cp /usr/local/bin/helm /bin/.
cp /usr/local/bin/tiller /bin/.

## Deploying Helm
kubectl --kubeconfig /root/.kube/config create serviceaccount --namespace kube-system tiller
kubectl --kubeconfig /root/.kube/config create clusterrolebinding tiller-cluster-role --clusterrole=cluster-admin --serviceaccount=kube-system:tiller
export HELM_HOME=/root/.helm
helm init --wait --service-account tiller
## Waiting for the tiller pod to be available
OUTPUT="$( (kubectl get pods --namespace kube-system -o json | jq .items[]) )"
while [ -z "$OUTPUT" ]
do
  echo "Still checking if tiller is up."
  OUTPUT="$( (kubectl get pods --namespace kube-system -o json | jq .items[]) )"
  sleep 5
done

OUTPUT="$( (kubectl get pods --namespace kube-system -o=custom-columns=NAME:.metadata.name,STATUS:.status.phase | grep deploy | awk '{print $2}') )"
while [[ $OUTPUT != Running ]]
do
  echo "Still checking if the tiller deployment pod is running"
  OUTPUT="$( (kubectl get pods --namespace kube-system -o=custom-columns=NAME:.metadata.name,STATUS:.status.phase | grep deploy | awk '{print $2}') )"
  sleep 5
done

## Deploying smart check
helm install --wait --set auth.masterPassword=trend1234 \
    --name deepsecurity-smartcheck \
    --set activationCode=${SC_ACTIVATION_CODE} \
    https://github.com/deep-security/smartcheck-helm/archive/master.tar.gz

## Waiting for smartcheck to have a URL
sleep 15
OUTPUT=$(kubectl get svc | grep proxy | awk '{print $4}')
while [[ ${OUTPUT} = '<none>' ]]
do
  echo "1 Still checking if Smart Check is available"
  OUTPUT=$(kubectl get svc | grep proxy | awk '{print $4}')
  sleep 5
done


## Getting the right values
SMART_CHECK=$(kubectl get svc proxy -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
SC_USERNAME=$(kubectl get secrets -o jsonpath='{ .data.userName }' deepsecurity-smartcheck-auth | base64 --decode)
SC_PASSWORD=$(kubectl get secrets -o jsonpath='{ .data.password }' deepsecurity-smartcheck-auth | base64 --decode)

## Waiting for smartcheck to be available
OUTPUT=$(curl -k -s -o /dev/null -w "%{http_code}" https://${SMART_CHECK}/login)
while [[ $OUTPUT != 200 ]]
do
  echo "Still checking if Smart Check is running"
  SMART_CHECK=$(kubectl get svc proxy -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
  SC_USERNAME=$(kubectl get secrets -o jsonpath='{ .data.userName }' deepsecurity-smartcheck-auth | base64 --decode)
  SC_PASSWORD=$(kubectl get secrets -o jsonpath='{ .data.password }' deepsecurity-smartcheck-auth | base64 --decode)
  OUTPUT=$(curl -k -s -o /dev/null -w "%{http_code}" https://${SMART_CHECK}/login)
  sleep 5
done

## Configuring smart check
mkdir /tmp/smartcheck && cd /tmp/smartcheck
aws s3 cp s3://${BUCKET_NAME}/${BUCKET_PREFIX}smart-check-helpers/Dockerfile Dockerfile
aws s3 cp s3://${BUCKET_NAME}/${BUCKET_PREFIX}smart-check-helpers/create-project.js create-project.js
docker build -t smartcheck-helper .
docker run smartcheck-helper https://${SMART_CHECK}/api/ ${SC_USERNAME} ${SC_PASSWORD} ${SMART_CHECK_PASSWORD}

# K8s Game Secret 
aws s3 cp s3://${BUCKET_NAME}/${BUCKET_PREFIX}secret.yml ./
kubectl create -f ./secret.yml
rm secret.yml

#Get DSM API Key
cd /root/
aws s3 cp s3://${BUCKET_NAME}/${BUCKET_PREFIX}scripts/getDSMApiKey.sh ./
chmod a+x getDSMApiKey.sh
./getDSMApiKey.sh ${DSM_USER}
rm getDSMApiKey.sh
mv api_key /home/ec2-user/repository/
mv eksPolicy.json /home/ec2-user/repository/
echo ${DSM_URL} > /home/ec2-user/repository/DSM_URL
cd -


# Removing all polices not needed anymore
aws iam detach-role-policy --role-name ${IAM_ROLE} --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy
aws iam detach-role-policy --role-name ${IAM_ROLE} --policy-arn arn:aws:iam::aws:policy/AmazonEKSServicePolicy
aws iam detach-role-policy --role-name ${IAM_ROLE} --policy-arn arn:aws:iam::aws:policy/AdministratorAccess


# DSA Installation
if [[ $(/usr/bin/id -u) -ne 0 ]]; then
    echo You are not running as the root user.  Please try again with root privileges.;
    logger -t You are not running as the root user.  Please try again with root privileges.;
    exit 1;
fi;


#Get the files for the inital git checkin
sudo -u ec2-user git config --global credential.helper '!aws codecommit credential-helper $@'
sudo -u ec2-user git config --global credential.UseHttpPath true
cd /home/ec2-user/repository
#echo ${GITURL}  > url
echo "BEGIN git clone ${GITURL}"
sudo -u ec2-user git clone ${GITURL}
echo "END git clone ${GITURL} "
cd SecJam-*
aws s3 cp s3://${BUCKET_NAME}/${BUCKET_PREFIX}example-app/ ./ --recursive
cp /root/.kube/config ./kubeconfig
mv /home/ec2-user/repository/api_key ./
mv /home/ec2-user/repository/DSM_URL ./
mv /home/ec2-user/repository/eksPolicy.json  ./
ECR_BASE=`echo $ECR_ADDRESS | cut -d '/' -f 1`
ECR_REPO=`echo $ECR_ADDRESS | cut -d '/' -f 2`
sed -i s/ECR_BASE/${ECR_BASE}/g ./pod.yml 
sed -i s/ECR_REPO/${ECR_REPO}/g ./pod.yml 
sed -i s/ECR_BASE/${ECR_BASE}/g ./app-protect/pod.yml 
sed -i s/ECR_REPO/${ECR_REPO}/g ./app-protect/pod.yml 
#echo "${SMART_CHECK}" > smartcheck
chown -R ec2-user:ec2-user *
sudo -u ec2-user git add *
sudo -u ec2-user git commit -m "Inital Checkin"
sudo -u ec2-user git push
cd -
#End git

#
# Wait for DSM
#

until curl -f $MANAGERURL --insecure
do
  sleep 2
done

if type curl >/dev/null 2>&1; then
  curl $MANAGERURL/software/deploymentscript/platform/linuxdetectscriptv1/ -o /tmp/PlatformDetection $CURLOPTIONS --insecure

  if [ -s /tmp/PlatformDetection ]; then
      . /tmp/PlatformDetection
      platform_detect

      if [[ -z "${linuxPlatform}" ]] || [[ -z "${isRPM}" ]]; then
         echo Unsupported platform is detected
         logger -t Unsupported platform is detected
         false
      else
         echo Downloading agent package...
         if [[ $isRPM == 1 ]]; then package='agent.rpm'
         else package='agent.deb'
         fi
         curl $MANAGERURL/software/agent/$linuxPlatform -o /tmp/$package $CURLOPTIONS --insecure

         echo Installing agent package...
         if [[ $isRPM == 1 && -s /tmp/agent.rpm ]]; then
           rpm -ihv /tmp/agent.rpm
         elif [[ -s /tmp/agent.deb ]]; then
           dpkg -i /tmp/agent.deb
         else
           echo Failed to download the agent package. Please make sure the package is imported in the Deep Security Manager
           echo logger -t Failed to download the agent package. Please make sure the package is imported in the Deep Security Manager
           false
         fi
      fi
  else
     echo "Failed to download the agent installation support script."
     logger -t Failed to download the Deep Security Agent installation support script
     false
  fi
else
  echo "Please install CURL before running this script."
  logger -t Please install CURL before running this script
  false
fi


sleep 15
/opt/ds_agent/dsa_control -r
/opt/ds_agent/dsa_control -a $ACTIVATIONURL


echo `date` > /tmp/finished
