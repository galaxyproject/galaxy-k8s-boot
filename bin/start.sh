#!/usr/bin/env bash

#BRANCH=41-fix-nfs
BRANCH=${BRANCH:-test-debian-image-prep}
SERVER=${SERVER:-ks-debian-test}
REPO=${REPO:-https://github.com/ksuderman/galaxy-k8s-boot}
DRY_RUN=""

# ANSI formatting
reset="\033[0m"
bold="\033[1m"

function hi() {
    echo -e "$bold$@$reset"
}

NAME=$(basename "$0")

function help() {
    cat << EOF

$(hi NAME)
    $NAME

$(hi DESCRIPTION)
    Quick-start wrapper around $(hi launch_vm.sh) with preset defaults for
    launching a Galaxy Kubernetes VM.

$(hi SYNOPSIS)
    $NAME [OPTIONS]

$(hi OPTIONS)
    $(hi -b)|$(hi --branch) BRANCH    Git branch to deploy. Default $(hi $BRANCH)
    $(hi -r)|$(hi --repo) URL         Git repository URL. Default $(hi $REPO)
    $(hi -s)|$(hi --server) NAME      VM instance name. Default $(hi $SERVER)
       $(hi --dry-run)          Save cloud-init config and exit
    $(hi -h)|$(hi --help)             Show this help message

$(hi DEFAULTS)
    The following values are passed to $(hi launch_vm.sh) and cannot be
    changed from this script:

    Disk size      $(hi 256) GB
    Values files   $(hi values/values.yml), $(hi values/v26.0.yml)

$(hi ENVIRONMENT)
    Options can also be set via environment variables:
    $(hi BRANCH)  $(hi REPO)  $(hi SERVER)

$(hi EXAMPLES)
    \$> $NAME
    \$> $NAME --dry-run
    \$> $NAME -b feature-branch -s my-galaxy-vm
    \$> BRANCH=feature-branch $NAME -s my-galaxy-vm

EOF
}

while [[ $# -gt 0 ]] ; do
	case $1 in
		-b|--branch) BRANCH=$2 ; shift ;;
		--dry-run) DRY_RUN=$1 ;;
		-r|--repo) REPO=$2 ; shift ;;
		-s|--server) SERVER=$2 ; shift ;;
		-h|--help|help)
			help
			exit
			;;
		*)
			echo "Unrecognized parameter $1"
			help
			exit 1
			;;
	esac
	shift
done
echo "Launching ${SERVER}"

bin/launch_vm.sh $SERVER $DRY_RUN\
  --git-repo $REPO \
  --git-branch $BRANCH \
  --disk-size 256 \
  -f values/values.yml \
  -f values/batch.yml \
  -f values/v26.1.yml
