# Galaxy Kubernetes Boot

Use this repo to deploy Galaxy. The repo contains Ansible playbooks to prepare a
cloud image and deploy a Galaxy instance. Galaxy is deployed on a Kubernetes
cluster using RKE2. The playbooks work on GCP, AWS, and OpenStack (e.g.,
Jetstream2).

## Overview

This repo is divided into two main parts:

1. **Image Preparation**: This part contains playbooks and scripts to prepare a
   cloud image with all necessary components pre-installed. See [Image
   Preparation](docs/ImagePreparation.md) for details.
2. **Deployment**: This part contains playbooks to deploy the prepared image
   onto a RKE2 Kubernetes cluster. The deployment playbook can also be used without a
   prepared image, but using a prepared image speeds up the deployment process.
   Documentation for the deployment process can be found below (Note: this part
   of the documentation is currently out of date so will require some
   interpretation and adjustment).

## Deployment

### Prerequisites

To run the playbook we need to install Ansible and some other optional requirements that are only needed to generate the inventory file with the `bin/inventory.sh` script. The easiest way to install the requirements is to use `pip`.

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

If the host is a barebones Ubuntu, Ansible can be installed with the following commands:

```bash
sudo apt install software-properties-common
sudo add-apt-repository --yes --update ppa:ansible/ansible
sudo apt install ansible
```

### Launching the VM

Use the provided launch script to create a VM. The script handles both
persistent disk creation and existing disk attachment scenarios.

The VM uses Ubuntu 24.04 image with a root file system of at least 30GB.
Security groups should have ports 22 and 80 open. The persistent disk is
automatically formatted, mounted at `/mnt/block_storage`, and configured for the
Galaxy deployment.

```bash
bin/launch_vm.sh -k "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC66Snr9..." INSTANCE_NAME
```

#### Script Parameters

- `-k, --ssh-key`: SSH public key for the ubuntu user (required)
- `-d, --disk-name`: Name of persistent disk (default: galaxy-data-INSTANCE_NAME)
- `-s, --disk-size`: Size of persistent disk (default: 150GB)
- `-p, --project`: GCP project ID (default: anvil-and-terra-development)
- `-z, --zone`: GCP zone (default: us-east4-c)
- `-m, --machine-type`: Machine type (default: e2-standard-4)
- `--ephemeral-only`: Create VM without persistent disk

#### Monitoring Deployment

After launching, you can monitor the deployment progress:

```bash
# Watch cloud-init output
gcloud compute ssh INSTANCE_NAME --command='sudo tail -f /var/log/cloud-init-output.log'

# Monitor deployment logs
gcloud compute ssh INSTANCE_NAME --command='sudo journalctl -f -u cloud-final'
```

Galaxy will be available at `http://INSTANCE_IP/` once deployment completes
(typically ~6 minutes).

#### Advanced: Manual VM Creation

If you prefer to use the `gcloud` command directly, you can do so with:

```bash
gcloud compute instances create ea-rke2-c \
  --project=anvil-and-terra-development \
  --zone=us-east4-c \
  --machine-type=e2-standard-4 \
  --image=galaxy-k8s-boot-v2025-09-26 \
  --image-project=anvil-and-terra-development \
  --boot-disk-size=100GB \
  --boot-disk-type=pd-balanced \
  --create-disk=name=galaxy-data-disk,size=150GB,type=pd-balanced,device-name=galaxy-data,auto-delete=no \
  --tags=k8s,http-server,https-server \
  --scopes=cloud-platform \
  --metadata=ssh-keys="ubuntu:ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC66Snr9/0wpnzOkseCDm5xwq8zOI3EyEh0eec0MkED32ZBCFBcS1bnuwh8ZJtjgK0lDEfMAyR9ZwBlGM+BZW1j9h62gw6OyddTNjcKpFEdC9iA6VLpaVMjiEv9HgRw3CglxefYnEefG6j7RW4J9SU1RxEHwhUUPrhNv4whQe16kKaG6P6PNKH8tj8UCoHm3WdcJRXfRQEHkjoNpSAoYCcH3/534GnZrT892oyW2cfiz/0vXOeNkxp5uGZ0iss9XClxlM+eUYA/Klv/HV8YxP7lw8xWSGbTWqL7YkWa8qoQQPiV92qmJPriIC4dj+TuDsoMjbblcgMZN1En+1NEVMbV ea_key_pair" \
  --metadata-from-file=user-data=bin/user_data.sh
```

For attaching an existing disk instead, use
`--disk=name=your-disk-name,device-name=galaxy-data,mode=rw` instead of the
`--create-disk` option.


## Deleting the VM

**Note:** If you will want to redeploy an existing instance (ie, keep the data),
before deleting it, make sure to record the ID of the Galaxy PVC. You can find
it by running:

```bash
kubectl get pvc -n galaxy
```

Before deleting the VM, uninstall the Galaxy Helm chart to ensure all resources
are properly cleaned up:

```bash
helm uninstall -n galaxy galaxy --wait
helm uninstall -n galaxy-deps galaxy-deps --wait
```
Then, delete the VM using:

```bash
gcloud compute instances delete INSTANCE_NAME --zone=us-east4-c [--quiet]
```

## TODO: Update docs below. Currently out of sync with the code.

### Automated deployment

There is a script that automates the deployment process available in
`bin/init_script.sh`. The script can be supplied as user data when launching the
VM and it will automatically set up the environment and run the playbook.

## Generating the inventory file for manual deployment

The inventory is a file that lists the servers to be configured and defines some variables that are used in the playbooks. There is a Bash script that generates the inventory file, or it can be created manually based on the template provided. There are example inventory files in the `inventories` directory, but they can not be used as-is as the IP addresses and SSH keys will need to be updated.

To generate the inventory file, run the following command:

```bash
bin/inventory.sh --name my-server --ip 1.2.3.4 --key ~/.ssh/my-key.pem > inventories/my-server.ini
```

If running the playbook on the server itself, there is `inventories/locahost` file available that captures the necessary variables.

## Running the playbook

### Installing Galaxy

Once the inventory file is created, we can run the playbooks to deploy the
Kubernetes cluster and the Galaxy instance. The playbook takes the arguments:

- `chart_values_file`: Optional. Path relative to `values` subfolder containing
  values that will be used to configure the Galaxy Helm chart. The default is
  `values.yml`.

```bash
ansible-playbook -i inventories/my-server.ini deploy-galaxy.yml --extra-vars "galaxy_admin_users=email@address.com"
```

Once the playbook completes, the Galaxy instance will be available at `http://<server-ip>/` after a few minutes.

### Adding users

By default, user registration is disabled on the Galaxy instance. To add users, you can use the `bin/add_user.sh` script. The script takes the following arguments:

- `host`: The IP address of the Galaxy server
- `galaxy_api_key`: The API key for the Galaxy admin user
- `email`: The email address of the Galaxy user to be added
- `password`: The password for the Galaxy user
- `username`: The username for the Galaxy user

Run the script with:

```bash
bin/add_user.sh <host> <galaxy_api_key> <email> <password> <username>
```

### Installing Pulsar

The playbook can set up a Pulsar node instead of Galaxy. The invocation process is the same with the only difference being the `application` variable.

```bash
ansible-playbook -i inventories/my-server.ini playbook.yml --extra-vars "application=pulsar" --extra-vars "pulsar_api_key=changeme"
```


## Managing the Kubernetes cluster

If you would like to manage the Kubernetes cluster, you can use the `kubectl` command on the server, or download the `kubeconfig` file from the server and use it on your local machine.

```bash
scp -i ~/.ssh/my-key.pem ubuntu@<server-ip>:/home/ubuntu/.kube/config ~/.kube/config
```
