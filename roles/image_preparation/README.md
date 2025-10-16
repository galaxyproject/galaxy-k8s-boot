# VM Image Preparation for Galaxy K8s Boot

## Overview

The playbook in this repo is used to build a VM image for deploying
Galaxy. Having a custom image allows for faster deployments and a more
consistent environment. The playbook is designed to work with Ubuntu. Once
built, the image can be used to quickly deploy Galaxy instances on Kubernetes
clusters using RKE2.

Many sample commands are provided that are specific to GCP, but the playbook can
be adapted for other cloud providers like AWS or OpenStack (e.g., Jetstream2).

## Benefits of Having a Custom Image

- **Faster deployments**: ~50% reduction in startup time
- **Ubuntu focused**: Simplified maintenance and testing
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

## Repo Files Structure

```
roles/image_preparation/
├── defaults/main.yml        # Simplified variables
├── tasks/
│   ├── main.yml             # Orchestrates all tasks
│   ├── base_packages.yml    # Ubuntu package installation
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

### 1. Launch a Ubuntu Instance

Get the latest base Ubuntu image (pick the `amd64` variant). The code has been
tested with the Ubuntu 24.04.

```bash
gcloud compute images list \
  --project=ubuntu-os-cloud \
  --filter="family=ubuntu-minimal-2404-lts AND status=READY" \
  --format="value(name)"
```

Update the `--image` parameter in the instance creation command, as well as
`--project`, `--zone`, `--service-account`, and `--metadata` as needed.

```bash
gcloud compute instances create ea-mi \
  --project=anvil-and-terra-development \
  --zone=us-east4-b \
  --machine-type=n1-standard-2 \
  --image=ubuntu-minimal-2404-noble-amd64-v20251002 \
  --image-project=ubuntu-os-cloud \
  --boot-disk-size=100GB \
  --tags=http-server,https-server \
  --service-account=ea-dev@anvil-and-terra-development.iam.gserviceaccount.com \
  --scopes=https://www.googleapis.com/auth/cloud-platform \
  --metadata=ssh-keys="ubuntu:ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC66Snr9/0wpnzOkseCDm5xwq8zOI3EyEh0eec0MkED32ZBCFBcS1bnuwh8ZJtjgK0lDEfMAyR9ZwBlGM+BZW1j9h62gw6OyddTNjcKpFEdC9iA6VLpaVMjiEv9HgRw3CglxefYnEefG6j7RW4J9SU1RxEHwhUUPrhNv4whQe16kKaG6P6PNKH8tj8UCoHm3WdcJRXfRQEHkjoNpSAoYCcH3/534GnZrT892oyW2cfiz/0vXOeNkxp5uGZ0iss9XClxlM+eUYA/Klv/HV8YxP7lw8xWSGbTWqL7YkWa8qoQQPiV92qmJPriIC4dj+TuDsoMjbblcgMZN1En+1NEVMbV ea_key_pair"
```

### 2. Prepare Image

```bash
# Create/update the inventory file with your instance details
cp inventories/image_prep.ini.example inventories/image_prep.ini

# Run the prep playbook
./bin/prepare_image.sh -i inventories/image_prep.ini
```

### 3. Create a Custom Image

Stop the instance and then create the image.

```bash
gcloud compute instances stop ea-mi --zone=us-east4-b
```
Create the image, updating the name and source disk as needed:

```bash
gcloud compute images create galaxy-k8s-boot-v2025-09-26 \
  --source-disk=ea-mi \
  --source-disk-zone=us-east4-b \
  --family=galaxy-k8s-boot \
  --storage-location=us
```

### 4. Deploy Galaxy Cluster

Once the image is created, you can deploy a Galaxy cluster using the prepared
image. Use the `playbook.yml` to set up the cluster, which has its own
documentation in the main README.

## Customization

Override variables in inventory or command line:

```bash
# Different RKE2 version
-e "rke2_version=v1.34.1+rke2r1"

# Different Helm version
-e "helm_version=v3.19.0"
```
