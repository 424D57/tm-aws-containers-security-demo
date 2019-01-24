FROM jenkins/jenkins:lts-alpine

# Setting user to Root to install aws cli
USER root

# Installing aws cli
RUN apk add --update \
    python \
    py-pip \
    docker \
    sudo \
    curl \
    jq \
  && pip install awscli \
  && rm -rf /var/cache/apk/*

RUN echo "jenkins   ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

# Need kubectl for deployment
COPY kubectl /bin/
COPY aws-iam-authenticator /bin/
COPY scan.sh	/bin/

# Going back to user Jenkins
USER jenkins

# Auto setuping Jenkins
ENV JAVA_OPTS="-Djenkins.install.runSetupWizard=false"

# Adding the admin user
COPY security.groovy /usr/share/jenkins/ref/init.groovy.d/security.groovy

# Installing scripts
COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN /usr/local/bin/install-plugins.sh < /usr/share/jenkins/ref/plugins.txt

# Configure Git
COPY gitconfig /var/jenkins_home/.gitconfig



