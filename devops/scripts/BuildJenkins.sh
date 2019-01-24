#!/bin/bash

##
##  Build Jenkins server
##

ACTIVATIONURL="dsm://${DSM_URL}:4120/"
MANAGERURL="https://${DSM_URL}:443"
CURLOPTIONS='--silent --tlsv1.2'
linuxPlatform='';
isRPM='';
JENKINS_USERNAME="admin"

# Configuting AWS Region
yum install -y jq
export AWS_REGION=$(curl -s 169.254.169.254/latest/dynamic/instance-identity/document | jq -r .region)
echo "export AWS_REGION=${AWS_REGION}" >> ~/.bash_profile
aws configure set default.region ${AWS_REGION}
aws configure get default.region


# Install Docker
yum -y update && sudo yum -y install python-pip git jq
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

# Generate selfsigned certificates
mkdir /certs
touch /certs/${DNS}.key
touch /certs/${DNS}.crt
openssl req  -new -newkey rsa:4096 -days 365 -nodes -x509 -subj "/C=US/ST=Trend/L=Dallas/O=Dis/CN=${DNS}" -keyout /certs/${DNS}.key -out /certs/${DNS}.crt


# Run Jenkins
aws s3 cp s3://${BUCKET_NAME}/${BUCKET_PREFIX}jenkins-container jenkins-container --recursive
cd jenkins-container
echo ${GITURL} | sed 's/\//\\\//g' > escaped_git
GIT=`cat escaped_git` ; sed -i s/GIT_URL/$GIT/g ./jenkins_volume/jobs/SecJam\ 2018/config.xml 
GIT=`cat escaped_git` ; sed -i s/GIT_URL/$GIT/g ./jenkins_volume/jobs/Get\ External\ IP/config.xml 
GIT=`cat escaped_git` ; sed -i s/GIT_URL/$GIT/g ./jenkins_volume/jobs/Update\ Deep\ Security\ Policy/config.xml
GIT=`cat escaped_git` ; sed -i s/GIT_URL/$GIT/g ./jenkins_volume/jobs/App\ Protect/config.xml
chown -R ec2-user jenkins_volume
mkdir secrets
echo ${JENKINS_USERNAME} > secrets/username
echo ${JENKINS_PASSWORD} > secrets/password
cp /bin/kubectl ./
cp /usr/bin/aws-iam-authenticator  ./
chmod a+x scan.sh
docker-compose up -d
##Sometimes docker-compose fails with:
#   Pulling proxy (jwilder/nginx-proxy:)...
#   unauthorized: authentication required
# So we try again.
until docker-compose up -d ; do sleep 1; done 
rm kubectl aws-iam-authenticator

#Get the files for the inital git checkin
sudo -u ec2-user git config --global credential.helper '!aws codecommit credential-helper $@'
sudo -u ec2-user git config --global credential.UseHttpPath true
sudo -u ec2-user cp /home/ec2-user/.gitconfig /jenkins-container/jenkins_volume/
#End git



# Install DSA
if [[ $(/usr/bin/id -u) -ne 0 ]]; then
    echo You are not running as the root user.  Please try again with root privileges.;
    logger -t You are not running as the root user.  Please try again with root privileges.;
    exit 1;
fi;

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
