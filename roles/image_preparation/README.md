# VM Image Preparation for Galaxy K8s Boot

## Overview

The playbook in this repo is used to build a VM image for deploying
Galaxy. Having a custom image allows for faster deployments and a more
consistent environment. The playbook supports both Debian and Ubuntu. Once
built, the image can be used to quickly deploy Galaxy instances on Kubernetes
clusters using RKE2.

Many sample commands are provided that are specific to GCP, but the playbook can
be adapted for other cloud providers like AWS or OpenStack (e.g., Jetstream2).

## Benefits of Having a Custom Image

- **Faster deployments**: ~50% reduction in startup time
- **Debian and Ubuntu support**: Auto-detects OS and configures accordingly
- **CVMFS ready**: Pre-configured Galaxy data access

The process will set up the following components on the image:

## Components Installed

### Essential Packages
- Python3 and pip with Kubernetes libraries
- Basic system utilities (curl, wget, git, jq, vim, etc.)
- NFS client for storage support

### Kubernetes Components
- **RKE2 prerequisites**: Required system packages and configurations
- **Helm**: Latest version for package management

### CVMFS Client
- Configured for the following Galaxy's CVMFS data repositories:
  - data.galaxyproject.org
  - cloud.galaxyproject.org

## Repo Files Structure

```
roles/image_preparation/
├── defaults/main.yml        # Simplified variables
├── tasks/
│   ├── main.yml             # Orchestrates all tasks
│   ├── base_packages.yml    # Package installation
│   ├── system_config.yml    # Kernel and system settings
│   ├── rke2_prerequisites.yml # RKE2 prerequisites installation
│   ├── helm.yml             # Helm installation
│   └── cleanup.yml          # Image cleanup

image_prep.yml               # Main playbook for building the image
playbook.yml                 # Deployment playbook using the prepared image

inventories/
└── image_prep.ini.example   # GCP-focused example

bin/prepare_image.sh         # Helper script
```

## Usage

### 1. Launch a Base Instance

#### Debian 12 (recommended)

Get the latest Debian 12 image:

```bash
gcloud compute images list \
  --project=debian-cloud \
  --filter="family=debian-12 AND status=READY" \
  --format="value(name)"
```

Launch a Debian 12 instance (note: default user is `debian`):

```bash
gcloud compute instances create ea-mi \
  --project=anvil-and-terra-development \
  --zone=us-east4-b \
  --machine-type=n1-standard-2 \
  --image-family=debian-12 \
  --image-project=debian-cloud \
  --boot-disk-size=100GB \
  --tags=http-server,https-server \
  --service-account=ea-dev@anvil-and-terra-development.iam.gserviceaccount.com \
  --scopes=https://www.googleapis.com/auth/cloud-platform \
  --metadata=ssh-keys="debian:ssh-rsa AAAAB3... your_key"
```

#### Ubuntu 24.04 (alternative)

Get the latest Ubuntu 24.04 image:

```bash
gcloud compute images list \
  --project=ubuntu-os-cloud \
  --filter="family=ubuntu-minimal-2404-lts AND status=READY" \
  --format="value(name)"
```

Launch an Ubuntu instance (note: default user is `ubuntu`):

```bash
gcloud compute instances create ea-mi \
  --project=anvil-and-terra-development \
  --zone=us-east4-b \
  --machine-type=n1-standard-2 \
  --image=ubuntu-minimal-2404-noble-amd64-v20260114 \
  --image-project=ubuntu-os-cloud \
  --boot-disk-size=100GB \
  --tags=http-server,https-server \
  --service-account=ea-dev@anvil-and-terra-development.iam.gserviceaccount.com \
  --scopes=https://www.googleapis.com/auth/cloud-platform \
  --metadata=ssh-keys="ubuntu:ssh-rsa AAAAB3... your_key"
```

### 2. Prepare Image

#### Customization

Set any variables in `defaults/main.yml` and create or update your inventory
file with the instance details:

```bash
cp inventories/image_prep.ini.example inventories/image_prep.ini
```

Set `ansible_user` in the inventory to match the OS (`debian` for Debian,
`ubuntu` for Ubuntu).

Then run the prep playbook to configure it:

```bash
./bin/prepare_image.sh -i inventories/image_prep.ini
```

### 3. Create a Custom Image

Stop the instance and then create the image.

```bash
gcloud compute instances stop ea-mi --zone=us-east4-b
```

Create the image, updating the name and source disk as needed.

```bash
gcloud compute images create galaxy-k8s-boot-v2026-02-20 \
  --source-disk=ea-mi \
  --source-disk-zone=us-east4-b \
  --family=galaxy-k8s-boot \
  --storage-location=us
```

Then delete the instance.

```bash
gcloud compute instances delete ea-mi --zone=us-east4-b --quiet
```

### 4. Deploy Galaxy

Once the image is created, you can deploy Galaxy using the prepared image. Use
the `playbook.yml` to set up the cluster, which has its own documentation in the
main README in this repo.

When launching with `bin/launch_vm.sh`, use `--user debian` for Debian-based
images or `--user ubuntu` for Ubuntu-based images.
