#!/bin/bash
for (( i=1; i<=150; i++ ))
do
   echo "Deleting team $i"
   aws cloudformation delete-stack --stack-name SecJam-team${i}
done
