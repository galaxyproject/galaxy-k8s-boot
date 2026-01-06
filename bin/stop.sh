#!/usr/bin/env bash
set -eu

DELETE_DISKS="no"
SERVER=${SERVER:-ks-batch-test}
QUIET=""
ZONE=${ZONE:-us-east4-c}

function help() {
	less -RX << EOF
	
NAME
    $0

SYNOPSIS
    $0 <server> [-z|--zone <zone>]

DESCRIPTION
    Stops a Google Cloud VM

OPTIONS
    -a, --all           delete all disks after the cluster
    -q, --quiet         don't prompt before deleting
    -z|--zone ZONE      the GCP zone where the VM is located
    -h|--help|help      prints this help message and exits
	
EXAMPLES
    $0 
    $0 my-server
    $0 my-server -z us-east1-b
    $0 --zone us-east1-b my-server
    
Press Q to quit

EOF
}
while [[ $# -gt 0 ]] ; do
	case $1 in
	    -a|--all) DELETE_DISKS="yes" ;;
	    -aq|-qa) DELETE_DISKS="yes" ; QUIET="--quiet" ;;
		-q|--quiet|-y|--yes) QUIET="--quiet" ;;
		-z|--zone) ZONE=$2 ; shift ;;
		-h|--help|help) help ; exit ;;
		*) SERVER=$1 ;;
	esac
	shift
done
gcloud compute instances delete $SERVER --zone $ZONE $QUIET

if [[ $DELETE_DISKS = "yes" ]] ; then
	for disk in $(gcloud compute disks list --filter="name~.*${SERVER}.*" --format='value(name)') ; do
		gcloud compute disks delete $disk --zone $ZONE $QUIET
	done
fi
