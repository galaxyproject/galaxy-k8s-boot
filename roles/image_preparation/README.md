# VM Image Preparation for Galaxy K8s Boot

## Overview

The playbook in this repo is used to build a VM image for deploying
Galaxy. Having a custom image allows for faster deployments and a more
consistent environment. The playbook supports both Debian and Ubuntu. Once
built, the image can be used to quickly deploy Galaxy instances on Kubernetes
clusters using RKE2.

Many sample commands are provided that are specific to GCP, but the playbook can
be adapted for other cloud providers like AWS or OpenStack (e.g., Jetstream2).

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
├── README.md
├── requirements.yml              # Role dependencies
├── defaults/
│   └── main.yml                  # Role variables with defaults
├── files/
│   └── container_images.yml      # List of container images to prefetch
├── meta/
│   └── main.yml                  # Role metadata
└── tasks/
    ├── main.yml                  # Orchestrates all tasks
    ├── base_packages.yml         # Package installation
    ├── cleanup.yml               # Image cleanup
    ├── container_prefetch.yml    # Container image prefetching
    ├── helm.yml                  # Helm installation
    ├── k3s_binary.yml            # k3s binary download
    ├── rke2_prerequisites.yml    # RKE2 prerequisites installation
    └── system_config.yml         # Kernel and system settings

image_prep.yml               # Main playbook for building the image
playbook.yml                 # Deployment playbook using the prepared image

inventories/
└── image_prep.ini.example   # GCP-focused example

bin/prepare_image.sh         # Helper script
```

## Usage

The `bin/prepare_image.sh` script handles the entire image build process end
to end: it creates a temporary GCE VM, runs the Ansible preparation playbook,
snapshots it as a GCE image, and deletes the VM.

```bash
./bin/prepare_image.sh
```

### Options

| Flag | Description | Default |
|------|-------------|---------|
| `--os` | Base OS preset: `debian12` or `ubuntu2404` | `debian12` |
| `--name` | Override output image name | `galaxy-k8s-boot-v{YYYY-MM-DD}` |
| `--zone` | GCP zone | `us-east4-c` |
| `--project` | GCP project | `anvil-and-terra-development` |
| `--machine-type` | VM machine type | `n1-standard-2` |
| `--vm-name` | Override temporary VM name | `galaxy-image-prep` |
| `--keep-vm` | Don't delete the VM after image creation | |
| `-v`, `--verbose` | Verbose Ansible output | |
| `-n`, `--dry-run` | Print the exact commands that would run, then exit | |

### Running Steps Individually

To get the exact commands for each step without executing them, use
`--dry-run`. This prints the full `gcloud` and `ansible-playbook` commands
with all resolved values, which you can copy and run manually.

```bash
./bin/prepare_image.sh --dry-run
./bin/prepare_image.sh --dry-run --os ubuntu2404 --zone us-central1-a
```

### Deploy Galaxy

Once the image is created, deploy Galaxy using the prepared image with
`playbook.yml`. See the main README for details.

When launching with `bin/launch_vm.sh`, use `--user debian` for Debian-based
images or `--user ubuntu` for Ubuntu-based images.
