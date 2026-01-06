#!/usr/bin/env bash

#BRANCH=41-fix-nfs
BRANCH=${BRANCH:-persistent-data-merged}
SERVER=${SERVER:-ks-dev-batch}
REPO=${REPO:-https://github.com/ksuderman/galaxy-k8s-boot}

echo "Launching ${SERVER}"

bin/launch_vm.sh $SERVER \
  --git-repo $REPO \
  --git-branch $BRANCH \
  --disk-size 256 \
  --reuse-existing-data


#--enable-gcp-batch \
#-f values/values.yml -f values/batch.yml -f values/v25.1-auto.yml -f values/rules.yml -f values/resource-params.yml -f values/probes.yml