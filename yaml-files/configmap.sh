#!/usr/bin/env bash



kubectl create clusterrolebinding dev-cluster-admin --clusterrole cluster-admin --serviceaccount dev:default

mkdir /data/deployment_no_replica
mkdir /data/deployment


namespace=dan-test

for deployment in $(kubectl get -o=name deployment --namespace=$namespace | sed "s/^.\{22\}//")
do
    kubectl get -o=yaml deployment.extensions/$deployment --namespace=$namespace --export > data/deployment/$deployment.yaml
   
    kubectl get -o=yaml deployment.extensions/$deployment --namespace=$namespace --export > data/deployment_no_replica/$deployment.yaml

done

file='ls /data/deployment_no_replica'

for eachfile in $files
do
   sed -i '' 's/replicas: [1-9]/replicas: 0/g' data/deployment_no_replica/$eachfile
done


#DELETE DEPLOYMENT

deployments=`ls /data/deployment`


for yaml_file in $deployment;
    do
    kubectl delete deployment $(echo $yaml_file | cut -f1 -d "."  ) --namespace=$namespace; 
done

sleep 600
