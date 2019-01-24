'use strict';

var AWS = require('aws-sdk');
AWS.config.update({region: 'us-east-1'});

var cloudformation = new AWS.CloudFormation();
var codecommit = new AWS.CodeCommit();


var deleteStack = async function(id){
  return await Promise.resolve(cloudformation.deleteStack({'StackName' : id}).promise());
};

var deleteStacks = async function(){
  try{
    var res = await Promise.resolve(cloudformation.listStacks({'StackStatusFilter': ['CREATE_COMPLETE', 'DELETE_FAILED', 'ROLLBACK_FAILED']}).promise());
    //console.log(res);
    var results = [];
    for (var i = 0; i < res.StackSummaries.length; i++){
      var id = res.StackSummaries[i].StackId;
      var data = await deleteStack(id);
      // wait 5 seconds
      await new Promise((resolve, reject) => setTimeout(resolve, 5000));
      results.push(data);
    };
    return results;
  }
  catch(err){
    return err
  };
}

var deleteRepository = async function(id){
  return await Promise.resolve(codecommit.deleteRepository({'repositoryName' : id}).promise());
};

var deleteRepositories = async function(){
  try{
    var res = await Promise.resolve(codecommit.listRepositories().promise());
    console.log(res);
    var results = [];
    for (var i = 0; i < res.repositories.length; i++){
      var id = res.repositories[i].repositoryName;
      var data = await deleteRepository(id);
      results.push(data);
    };
    return results;
  }
  catch(err){
    return err
  };
};


deleteStacks()
  .then(res =>{
    console.log(res);
  });
deleteRepositories()
  .then(res =>{
    console.log(res);
  });
