# Ansible Deployment Role for Galaxy on Kubernetes

An Ansible role for deploying Galaxy on Kubernetes (RKE2). This role provides a
unified, modular approach to setting up the entire Galaxy infrastructure stack.

## Features

- **Single-node RKE2 cluster setup** from a bare Ubuntu VM or pre-prepared image
- **NFS storage provisioner** using Ganesha NFS
- **Kubernetes storage classes** for persistent volumes
- **NGINX ingress controller** for external access
- **Galaxy application deployment** using Helm charts
- **Pulsar application deployment** for distributed job execution
- **Modular task structure** - enable/disable components as needed

## Role Structure

```
galaxy_k8s_deployment/
├── tasks/
│   ├── main.yml                  # Main orchestrator
│   ├── system_setup.yml          # System packages and Helm installation
│   ├── rke2_setup.yml            # RKE2 Kubernetes cluster setup
│   ├── nfs_setup.yml             # NFS provisioner setup
│   ├── storage_setup.yml         # Kubernetes storage classes
│   ├── ingress_setup.yml         # NGINX ingress controller
│   ├── galaxy_application.yml    # Galaxy Helm deployment
│   └── pulsar_application.yml    # Pulsar Helm deployment
├── defaults/
│   └── main.yml                  # Default variables
├── handlers/
│   └── main.yml                  # Service handlers
├── meta/
│   └── main.yml                  # Role metadata and dependencies
└── README.md                     # This file
```

## Requirements

- Ansible >= 2.10
- Ubuntu 24.04
- Python 3
- Kubernetes collection: `kubernetes.core`
- Community collections: `community.general`, `ansible.posix`

Install required collections:
```bash
ansible-galaxy install -r requirements.yml
```

## Role Variables

### Component Control Flags

Enable or disable components by setting these boolean variables (defaults are
shown):

```yaml
setup_system: false         # Install system packages and Helm on a bare VM
setup_rke2: true            # Setup RKE2 cluster
setup_nfs: true             # Setup NFS provisioner
setup_storage: true         # Configure Kubernetes storage
setup_ingress: true         # Install NGINX ingress
deploy_galaxy: true         # Deploy Galaxy application
deploy_pulsar: false        # Deploy Pulsar application
```

### CVMFS Configuration

CVMFS is automatically installed when `setup_system: true`. To disable CVMFS installation, set `setup_cvmfs: false`.

```yaml
setup_cvmfs: true                          # Install CVMFS (when setup_system is true)
cvmfs_role: client                         # CVMFS role type
galaxy_cvmfs_repos_enabled: config-repo    # Galaxy CVMFS repos to enable
cvmfs_quota_limit: 4000                    # CVMFS cache size (MB)
cvmfs_http_proxies: ["DIRECT"]             # HTTP proxies for CVMFS
```

### RKE2 Configuration

```yaml
rke2_token: "default-token-change-me"      # Cluster join token
rke2_disable:                              # Components to disable
  - rke2-traefik
  - rke2-ingress-nginx
rke2_additional_sans: []                   # Additional TLS SANs
rke2_debug: false                          # Enable debug mode
```

### NFS Storage Configuration

```yaml
nfs_version: "1.8.0"                       # Ganesha NFS chart version
nfs_persistence_storage_class: blockstorage
nfs_size: "25Gi"                           # NFS backing storage size
nfs_default: false                         # Set as default storage class
nfs_allow_expansion: true
nfs_reclaim: Delete
```

### Ingress Configuration

```yaml
ingress_version: "4.13.2"                  # NGINX ingress chart version
```

### Galaxy Application Configuration

```yaml
galaxy_chart: cloudve/galaxy
galaxy_chart_version: "6.5.0"              # Galaxy chart version
galaxy_deps_version: "1.1.1"               # Galaxy dependencies version
galaxy_values_file: "values/values.yml"    # Path to Galaxy values file
galaxy_persistence_size: "20Gi"            # Galaxy data volume size
galaxy_db_password: "galaxydbpassword"     # PostgreSQL password
galaxy_user: "admin@galaxy.org"            # Galaxy admin user
galaxy_api_key: ""                         # Galaxy API key
galaxy_job_max_cores: 1                    # Max CPU cores per job
galaxy_job_max_mem: 4                      # Max memory per job (GB)
```

### Pulsar Application Configuration

```yaml
pulsar_chart: cloudve/pulsar
pulsar_chart_version: "0.2.0"              # Pulsar chart version
pulsar_deps_version: "1.1.1"               # Pulsar dependencies version
pulsar_api_key: ""                         # Pulsar API key
```

## Dependencies

This role has optional dependencies:

- `galaxyproject.cvmfs` - For CVMFS repository access (automatically installed when `setup_system: true`, can be disabled with `setup_cvmfs: false`)

## Example Playbooks

### Quick Start: Single-Node Galaxy Deployment

```yaml
---
- name: Deploy Galaxy on Kubernetes
  hosts: vm
  gather_facts: true
  become: true
  roles:
    - role: galaxy_k8s_deployment
      vars:
        setup_system: false  # Pre-prepared image (Helm already installed)
        setup_rke2: true
        setup_nfs: true
        setup_storage: true
        setup_ingress: true
        deploy_galaxy: true
        rke2_token: "my-secure-token"
        galaxy_values_file: "values/my-galaxy-config.yml"
        galaxy_api_key: "my-api-key"
```

### Deployment on Bare Ubuntu VMs

For fresh Ubuntu installations requiring full setup:

```yaml
---
- name: Deploy Galaxy on bare Ubuntu VM
  hosts: vm
  gather_facts: true
  become: true
  roles:
    - role: galaxy_k8s_deployment
      vars:
        setup_system: true   # Install system packages and Helm
        setup_rke2: true
        setup_nfs: true
        setup_storage: true
        setup_ingress: true
        deploy_galaxy: true
        rke2_token: "my-secure-token"
        galaxy_values_file: "values/my-galaxy-config.yml"
        galaxy_api_key: "my-api-key"
```

### Pulsar Deployment

```yaml
---
- name: Deploy Pulsar for distributed job execution
  hosts: vm
  gather_facts: true
  become: true
  roles:
    - role: galaxy_k8s_deployment
      vars:
        setup_system: false  # Pre-prepared image
        setup_rke2: true
        setup_nfs: true
        setup_storage: true
        setup_ingress: true
        deploy_pulsar: true
        pulsar_api_key: "my-pulsar-key"
```

## Usage with Main Playbooks

This role is used by the main playbook in the repository:

### playbook.yml

Full deployment including multi-node RKE2 option:

```bash
ansible-playbook -i inventory playbook.yml -e "galaxy_user=admin@galaxyproject.org"
```

## Handlers

The role includes handlers for service management:

- `restart rke2-server` - Restarts the RKE2 server service

## Kubeconfig Location

After RKE2 setup, the kubeconfig is available at:
- Path: `/etc/rancher/rke2/rke2.yaml`
- Set as fact: `kubeconfig_path`

## Troubleshooting

### RKE2 Cluster Issues

If the cluster fails to start:
1. Check logs: `journalctl -u rke2-server -f`
2. Verify token: Ensure `rke2_token` is set
3. Check firewall: Port 6443 must be accessible

### Storage Issues

If storage provisioning fails:
1. Verify storage class exists: `kubectl get storageclass`
2. Check NFS provisioner: `kubectl get pods -n nfs-provisioner`
3. Review PVC status: `kubectl get pvc -A`

### Galaxy Deployment Issues

If Galaxy fails to deploy:
1. Check namespace: `kubectl get pods -n galaxy`
2. Review helm release: `helm list -n galaxy`
3. Check values file: Ensure `galaxy_values_file` path is correct
