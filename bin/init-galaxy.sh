#!/usr/bin/env bash
set -eu

# if [[ $# < 1 ]] ; then
# 	echo "USAGE: ./kube.sh <CLUSTER NAME>"
# 	echo
# 	exit 1
# fi

SERVER=${SERVER:-ks-gcp-test}
CLOUD=${CLOUD:-gcp}
ADMIN_EMAIL=admin@galaxyproject.org

CREATE_USER=""
GET_KEY=""
GET_URL=""

# gcloud compute scp ubuntu@$SERVER:/home/ubuntu/.kube/config ~/.kube/configs/$CLOUD
# kubectl config set-cluster default --server=https://$ip:6443 --kubeconfig=/Users/suderman/.kube/configs/$CLOUD
# 
# echo "Updating ABM configuration"
# if [[ -z $(abm config list | grep $cloud) ]] ; then
# 	echo "Creating an ABM configuration for $cloud"
# 	abm config create $cloud ~/.kube/configs/$cloud
# fi

while [[ $# -gt 0 ]] ; do
  case $1 in
    key) GET_KEY="true" ; CREATE_USER="" ;;
    url) GET_URL="true" ;;
    user) GET_KEY="" ; CREATE_USER="true" ;;
    -c|--cloud) CLOUD=$2 ; shift ;;
    -e|--email) ADMIN_EMAIL=$2 ; shift ;;
    -s|--server) SERVER=$2 ; shift ;;
  esac
  shift
done

IP=$(gcp ip get $SERVER)
if [[ -n $GET_URL ]] ; then
	abm config url $CLOUD "http://$IP"	
fi

if [[ -n $GET_KEY ]] ; then
	# Ensure the default Galaxy user has been created.
	curl http://$IP > /dev/null
	echo "Getting user API key for $CLOUD"
	abm config key $CLOUD galaxypassword
	key=$(abm $CLOUD user key dev)
	if [[ -z $key ]] ; then
		echo "Unable to get the API key for user dev"
		exit 1
	fi
	echo "The API key is $key"
	abm config key $CLOUD $key
fi

#ip=$(gcloud compute instances list | grep $SERVER | awk '{print $5}')
#abm config url $CLOUD http://$ip
#abm config key $CLOUD galaxypassword

#if [[ $CREATE_USER = "true" ]] ; then
#  echo "Creating the Galaxy user"
#  key=$(abm $cloud user create ksuderman admin@example.com galaxypassword | jq -r .key)
#else
#  key=$(abm $CLOUD user key $ADMIN_EMAIL)
#fi
#abm config key $CLOUD $key

#abm $cloud history import metaphlan
#abm $cloud history import rna-20
abm $CLOUD history import variant-test
# abm $cloud workflow import metaphlan
abm $CLOUD workflow import variant --no-tools
abm $CLOUD dataset import --create FastP --name forward fastp-forward
abm $CLOUD dataset import --history FastP --name reverse fastp-reverse
