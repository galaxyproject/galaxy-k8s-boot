# Galaxy Kubernetes Boot

Use this repo to deploy Galaxy. The repo contains Ansible playbooks to prepare a
cloud image and deploy a Galaxy instance. Galaxy is deployed on a Kubernetes
cluster using RKE2. The playbooks work on GCP, AWS, and OpenStack (e.g.,
Jetstream2).

The deployed Galaxy can run jobs on the same K8s cluster but the intent of this
deployment model is for Galaxy to submit jobs to an external job management
system, such as GCP Batch.

## Overview

This repo is divided into two main parts:

1. **Image Preparation**: This part contains a playbook to prepare a cloud image
   with all necessary components pre-installed. See the [Image
   Preparation](roles/image_preparation/README.md) documentation for details.
2. **Deployment**: This part contains a playbook to deploy the prepared image
   onto a RKE2 Kubernetes cluster. The deployment playbook can also be used without a
   prepared image, but using a prepared image speeds up the deployment process.
   Documentation for the deployment process can be found below.

## Deployment

### Automated Deployment on GCP

To deploy Galaxy on a VM on GCP, use the provided launch script to create a VM.
The script will create a VM and install the necessary software to run the
Ansible playbook that deploys Galaxy.

The script needs a pre-built Ubuntu 24.04 image. Internally, the script uses
`cloud-init` to bootstrap the VM and run the Ansible playbook. The `cloud-init`
script is located in `bin/user_data.sh`. The script will clone this repository
and run the playbook with the appropriate variables. If you want to customize
the deployment, it is recommended to perform these steps manually (see
documentation below).

Basic usage:

```bash
bin/launch_vm.sh -k "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC66Snr9..." INSTANCE_NAME
```

Galaxy will be available at `http://INSTANCE_IP/` once deployment completes
(typically ~6 minutes).

#### Script Parameters

- `-k, --ssh-key`: SSH public key for the ubuntu user (required)
- `-d, --disk-name`: Name of persistent disk (default: galaxy-data-INSTANCE_NAME)
- `-i, --machine-image`: Machine image name (default: galaxy-k8s-boot-v2025-11-14)
- `-m, --machine-type`: Machine type (default: e2-standard-4)
- `-p, --project`: GCP project ID (default: anvil-and-terra-development)
- `-s, --disk-size`: Size of persistent disk (default: 150GB)
- `-z, --zone`: GCP zone (default: us-east4-c)
- `-g, --git-repo`: Git repository URL (default: https://github.com/galaxyproject/galaxy-k8s-boot.git)
- `-b, --git-branch`: Git branch to deploy (default: master)
- `--ephemeral-only`: Create VM without persistent disk

#### Examples

**Basic deployment:**
```bash
bin/launch_vm.sh -k "ssh-rsa AAAAB3..." my-galaxy-vm
```

**Custom git repository and branch (for testing/development):**
```bash
bin/launch_vm.sh -k "ssh-rsa AAAAB3..." \
  -g "https://github.com/username/galaxy-k8s-boot.git" \
  -b "feature-branch" \
  my-test-vm
```

**With custom machine type and larger disk:**
```bash
bin/launch_vm.sh -k "ssh-rsa AAAAB3..." \
  -m "e2-standard-8" \
  -s "500GB" \
  my-production-vm
```

### Manual Deployment

#### Prerequisites

To run the playbook locally, we need to install the dependencies for this repo.

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

#### Creating a VM

Use the `gcloud` command to create a VM instance.

```bash
gcloud compute instances create ea-rke2-c \
  --project=anvil-and-terra-development \
  --zone=us-east4-c \
  --machine-type=e2-standard-4 \
  --image=galaxy-k8s-boot-v2025-11-14 \
  --image-project=anvil-and-terra-development \
  --boot-disk-size=100GB \
  --boot-disk-type=pd-balanced \
  --create-disk=name=galaxy-data-disk,size=150GB,type=pd-balanced,device-name=galaxy-data,auto-delete=yes \
  --tags=k8s,http-server,https-server \
  --scopes=cloud-platform \
  --metadata=ssh-keys="ubuntu:ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC66Snr9/0wpnzOkseCDm5xwq8zOI3EyEh0eec0MkED32ZBCFBcS1bnuwh8ZJtjgK0lDEfMAyR9ZwBlGM+BZW1j9h62gw6OyddTNjcKpFEdC9iA6VLpaVMjiEv9HgRw3CglxefYnEefG6j7RW4J9SU1RxEHwhUUPrhNv4whQe16kKaG6P6PNKH8tj8UCoHm3WdcJRXfRQEHkjoNpSAoYCcH3/534GnZrT892oyW2cfiz/0vXOeNkxp5uGZ0iss9XClxlM+eUYA/Klv/HV8YxP7lw8xWSGbTWqL7YkWa8qoQQPiV92qmJPriIC4dj+TuDsoMjbblcgMZN1En+1NEVMbV ea_key_pair"
```

For attaching an existing disk instead, use
`--disk=name=your-disk-name,device-name=galaxy-data,mode=rw` instead of the
`--create-disk` option.

> [!CAUTION]
> **Note:** Reattaching an existing disk does not currently work. Namely, NFS
> provisioner will create a new PVC and CNPG will create a new cluster each time
> this playbook is run, effectively resulting in a new, empty Galaxy instance.
> This is a known issue and will be addressed in future releases.

If you'd like to replicate the automated deployment, add the following option to
the `gcloud` command:

```bash
--metadata-from-file=user-data=bin/user_data.sh
```

#### Running the Playbook

Create an inventory file for the VM:

```bash
bin/inventory.sh --name gcp --key my-key.pem --ip 11.22.33.44 > inventories/vm.ini
```

Then run the playbook. Check out the [examples](command_examples.md) for different
ways to run the playbook.

```bash
ansible-playbook -i inventories/vm.ini playbook.yml --extra-vars "galaxy_user=admin@email.com"
```

Galaxy will be available at `http://INSTANCE_IP/` once deployment completes
(typically ~6 minutes).

### Monitoring Deployment

After launching, you can ssh into the VM to monitor the deployment progress:

```bash
# Watch cloud-init output
sudo tail -n +1 -f /var/log/cloud-init-output.log

# Monitor deployment logs
sudo journalctl -f -u cloud-final
```

## Deleting the VM

> [!CAUTION]
> **Note:** Redeploying an instance does not currently work so this
> bit is left as a reminder of how to do this once the issue is fixed. If you
> will want to redeploy an existing instance (ie, keep the data), before
> deleting it, make sure to record the ID of the Galaxy PVC. You can find it by
> running:
> ```bash
> kubectl get pvc -n galaxy
> ```

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

## Installing Pulsar

The playbook can set up a Pulsar node instead of Galaxy. The invocation process is the same with the only difference being the `application` variable.

```bash
ansible-playbook -i inventories/vm.ini playbook.yml --extra-vars "application=pulsar" --extra-vars "pulsar_api_key=changeme"
```

## Managing the Kubernetes cluster

If you would like to manage the Kubernetes cluster, you can use the `kubectl` command on the server, or download the `kubeconfig` file from the server and use it on your local machine.

```bash
scp -i my-key.pem ubuntu@<server-ip>:/home/ubuntu/.kube/config ~/.kube/config
```
