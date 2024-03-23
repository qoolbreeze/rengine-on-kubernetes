#!/bin/bash

#environment to set, unquote if necessary
#ns="<namespace>"

echo "be sure to be authenticated to your cluster before processing"

if [ -z ${ns+x} ]; then
  read -p "Enter namespace: " ns
fi

echo "Will deploy rengine on namespace ${ns}"

# replace values in yaml files
cp -R deployment/ deploy_temp
cd deploy_temp
sed -i "s/<ns>/${ns}/g" *.yaml

# create random secrets
head /dev/urandom | tr -dc "[0-9a-zA-Z]" | head -c 20 > rengine_postgres_password
head /dev/urandom | tr -dc "[0-9a-zA-Z]" | head -c 20 > rengine_admin_password

# add secrets
kubectl create secret generic rengine-secrets --from-file=rengine_postgres_password --from-file rengine_admin_password --namespace $ns
kubectl create configmap rengine-nginx-conf --from-file=nginx.conf --namespace=$ns
echo "Web admin password will be : $(cat rengine_admin_password)"
rm rengine_postgres_password rengine_admin_password

# deploy services
kubectl apply -f db-deployment.yaml --namespace $ns
sleep 10 #wait for db to be deployed
kubectl apply -f redis-deployment.yaml --namespace $ns
kubectl apply -f celery-worker-deployment.yaml --namespace $ns
kubectl apply -f celery-beat-deployment.yaml --namespace $ns
kubectl apply -f rengine-deployment.yaml --namespace $ns
sleep 60 # takes 60 seconds
kubectl apply -f nginx-deployment.yaml --namespace $ns
kubectl apply -f ingress-deployment.yaml --namespace $ns

# display url
sleep 2
url=$(cat ingress-deployment.yaml  | grep "Host" | cut -d '`' -f2)
status_code=$(curl --write-out '%{http_code}' --silent --output /dev/null "https://${url}/")

if [[ "${status_code}" -eq "200" ]] ; then
  echo "deployment success. You can now go to https://${url}"
  cd ..
  rm -rf deploy_temp
  exit 0
else
  echo "deployment failed. Try to debug using the command :\n kubectl get all -n $ns"
  exit 1
fi
