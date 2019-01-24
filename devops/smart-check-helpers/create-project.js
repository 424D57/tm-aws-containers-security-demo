'use strict';

process.env.NODE_TLS_REJECT_UNAUTHORIZED = '0';
const axios = require('axios');

var user, password, newPassword, registryId, url = '';

// If the provided Arguments are not right
if (process.argv.length <= 2){
  console.log('use: https://smart-check/api/ username oldpassword newpassword')
  return -1
}
else{
  url = process.argv[2]
  user = process.argv[3];
  password = process.argv[4];
  newPassword = process.argv[5];
  registryId = ''
}

const req = axios.create({
  baseURL: url,
  timeout: 1000,
  headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json'
    },
})

var login = function(username, password){
  var loginData = {
    "user": {
      "userID": username,
      "password": password
    }
  };
  return new Promise(function (fulfill, reject){
    req.post('sessions', loginData)
      .then(response => {
        fulfill(response.data);
      })
      .catch(error => {
        reject(error.response.status + '\n' + JSON.stringify(error.response.data, null, 4));
      });
  });
};

var changePassword = function(user, oldPassword, newPassword){
  var data = {
    "oldPassword": oldPassword,
    "newPassword": newPassword
  };
  return new Promise(function (fulfill, reject){
    req.post('users/' + user + '/password', data)
      .then(response => {
        fulfill(response.data);
      })
      .catch(error => {
        reject(error.response.status + '\n' + JSON.stringify(error.response.data, null, 4));
      });
  });
};

var getRegistries = function(){
  return new Promise(function (fulfill, reject){
    req.get('registries')
      .then(response => {
        fulfill(response.data);
      })
      .catch(error => {
        reject(error.response.status + '\n' + JSON.stringify(error.response.data, null, 4));
      });
  });
};

var createAwsRegistry = function(){
  var data = {
    "name": "My Great Registry",
    "description": "This registry is the one used for the SecJam!",
    "credentials":{
      "aws": {
        "region": "us-east-1",
      }
    },
    "insecureSkipVerify": false,
    "schedule": true
  };
  return new Promise(function (fulfill, reject){
    req.post('registries', data)
      .then(response => {
        fulfill(response.data);
      })
      .catch(error => {
        reject(error.response.status + '\n' + JSON.stringify(error.response.data, null, 4));
      });
  });
};

var listRegistryImages = function(registryId){
  return new Promise(function (fulfill, reject){
    req.get('registries/' + registryId + '/images')
      .then(response => {
        fulfill(response.data);
      })
      .catch(error => {
        reject(error.response.status + '\n' + JSON.stringify(error.response.data, null, 4));
      });
  });
};

var scanRegistryImage = function(registryId, repository, tag){
  var data = {
    "source":{
      "repository": repository,
      "tag": tag
    }
  };
  return new Promise(function (fulfill, reject){
    req.post('registries/' + registryId + '/scans', data)
      .then(response => {
        fulfill(response.data);
      })
      .catch(error => {
        reject(error.response.status + '\n' + JSON.stringify(error.response.data, null, 4));
      });
  });
};

//First it is going to log in and retrieve the token
login(user, password)
  .then(res => {
    console.log(res);
    var token = res.token;
    req.defaults.headers.common['Authorization'] = "Bearer " + token;
    var userId = res.user.id;
    //Now, it is time to change the password for the first use.
    return changePassword(userId, password, newPassword);
  })
  .then(res => {
    console.log(res);
    //Finally, we are going to create the association with the ECR
    return createAwsRegistry();
  })
  .then(res => {
    //just making sure everything is there
    return getRegistries();
  })
  .then(res => {
    registryId = res.registries[0].id;
    console.log(registryId);
    //Listing the images so we can scan it.
    return listRegistryImages(registryId);
  })
  .then(res => {
    console.log(res);
    var repository = res.images[0].repository;
    var tag = res.images[0].tag;
    //finally scanning it!
    return scanRegistryImage(registryId, repository, tag);
  })
  .then(res =>{
    console.log(JSON.stringify(res, null, 4));
  })
  .catch(err => {
    // in case something goes down...
    console.log(JSON.stringify(err, null, 4));
  });
// Happy smart checking!
