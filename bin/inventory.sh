#!/usr/bin/env bash
set -eu

reset="\033[0m"
bold="\033[1m"

NAME=$(basename $0)

user=ubuntu
key=~/.ssh/id_rsa
ip=
name=

# Function used to highlight text.
function hi() {
    echo -e "$bold$@$reset"
}

function usage() {
	less -RX << EOF

$(hi NAME)
    $NAME

$(hi DESCRIPTION)
    Generate an Ansible inventory file for RKE2 deployment.

$(hi SYNOPSIS)
    $NAME [OPTIONS]

$(hi OPTIONS)
    $(hi -i)|$(hi --ip)      public ip address of the server. Required.
    $(hi -k)|$(hi --key)     path to the public SSH key used to connect to the server. Default is $(hi $key).
    $(hi -n)|$(hi --name)    hostname for the server. Required.
    $(hi -u)|$(hi --user)    username used to connect to the server.  Default is $(hi $user).
    $(hi -h)|$(hi --help)    print this help message and exit.

Press $(hi Q) to exit

EOF
}

while [[ $# > 0 ]] ; do
	case $1 in
		-n|--name)
			name=$2
			shift
			;;
		-i|--ip)
			ip=$2
			shift
			;;
		-u|--user)
			user=$2
			shift
			;;
		-k|--key)
			key=$2
			shift
			;;
		-h|--help|help)
			usage
			exit
			;;
		*)
			echo "ERROR: Invalid option $1"
			usage
			exit
			;;
	esac
	shift
done

bin/render_template.py -t templates/inventory.ini.j2 name=$name ip=$ip user=$user key=$key
