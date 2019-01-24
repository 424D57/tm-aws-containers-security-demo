# specify the node base image with your desired version node:<version>
FROM node:11

# Set the right user
USER node

# Create and change to app folder
RUN mkdir -p /home/node/app
WORKDIR /home/node/app

# Install the only dependency
RUN npm install aws-sdk csvtojson

# Copy the script to the image
COPY . /home/node/app

# run it!
ENTRYPOINT ["node", "secjam-deploy.js"]
