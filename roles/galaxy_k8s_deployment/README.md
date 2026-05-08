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
nfs_size: "139Gi"                          # NFS backing storage size
nfs_default: false                         # Set as default storage class
nfs_allow_expansion: true
nfs_reclaim: Retain
```

### Kubernetes Storage Configuration

```yaml
cluster_hostname: galaxy                   # Cluster hostname
cinder_csi_version: "2.31.2"               # Cinder CSI version (if used)
block_storage_disk_path: /mnt/block_storage # Local path to NFS backing disk
postgres_storage_disk_path: /mnt/postgres_storage # Local path to PSQL backing disk
setup_postgres_storage: true               # Setup local-path storage for PostgreSQL
```

### CNPG and Restoration Configuration

```yaml
setup_cert_manager: false                  # Required for CNPG skip-initdb plugin
cert_manager_version: "v1.20.0"            # cert-manager chart version
cnpg_skip_initdb_enabled: true             # Enable PostgreSQL existing data reuse
cnpg_skip_initdb_image: "quay.io/galaxyproject/cnpg-i-skip-initdb:0.1"
cnpg_skip_initdb_namespace: "galaxy-deps"  # Must match CNPG operator namespace
cnpg_skip_initdb_plugin_name: "cnpg-i-skip-initdb.leonardoce.github.com"
restore_galaxy: false                      # Detect and restore existing Galaxy data
```

### Ingress Configuration

```yaml
ingress_version: "4.13.2"                  # NGINX ingress chart version
```

### Galaxy Application Configuration

```yaml
galaxy_chart: cloudve/galaxy
galaxy_chart_version: "6.7.2"              # Galaxy chart version
galaxy_deps_version: "1.1.1"               # Galaxy dependencies version
galaxy_values_files: ["values/values.yml"] # Path to Galaxy values files
galaxy_persistence_size: "128Gi"           # Galaxy data volume size
galaxy_db_password: "galaxydbpassword"     # PostgreSQL password
galaxy_user: "default-user@galaxyproject.org" # Galaxy admin user
galaxy_bootstrap_api_key: ""               # Galaxy bootstrap API key
galaxy_import_profile:                     # Helm values files for postInstall imports
  - "files/profiles/anvil.yaml"            # Set to [] to disable post-install imports
galaxy_job_max_cores: 1                    # Max CPU cores per job
galaxy_job_max_mem: 4                      # Max memory per job (GB)
```

### Automatic Data Import

`galaxy_import_profile` is a list of Helm values files merged into the Galaxy
chart deployment to configure the [postInstall job][abm-docs]. By default the
bundled AnVIL profile (`files/profiles/anvil.yaml`) is used, which enables the
postInstall job and imports sample RNA-seq datasets and a workflow after
deployment. Set `galaxy_import_profile: []` to skip post-install imports
entirely.

**Requirements**: Galaxy Helm chart 6.8.0+, ABM 2.12.0+.

To define custom imports, create a Helm values file with a `postInstallJob`
block and reference it via `galaxy_import_profile`:

```yaml
galaxy_import_profile:
  - "values/my-imports.yaml"
```

```yaml
# values/my-imports.yaml
postInstallJob:
  enabled: true
  bootstrapConfig: |
    datasets:
      "Tutorial Data":
        - "https://zenodo.org/records/13987631/files/SRR5085167_forward.fastqsanger.gz"
        - "https://zenodo.org/records/13987631/files/SRR5085167_reverse.fastqsanger.gz"
        - "https://zenodo.org/records/13987631/files/Saccharomyces_cerevisiae.R64-1-1.113.gtf"
    workflows:
      - "https://raw.githubusercontent.com/galaxyproject/iwc/refs/heads/main/workflows/transcriptomics/rnaseq-pe/rnaseq-pe.ga"
```

The `bootstrapConfig` format supports:
- **datasets**: Import files into named histories
- **workflows**: Import `.ga` workflow files
- **histories**: Import exported Galaxy history archives
- **workflows-no-tools**: Import workflows without installing tools

See the [ABM documentation][abm-docs] for the complete configuration format.

[abm-docs]: https://github.com/galaxyproject/gxabm

### Pulsar Application Configuration

```yaml
pulsar_chart: cloudve/pulsar
pulsar_chart_version: "0.2.0"              # Pulsar chart version
pulsar_deps_version: "1.1.1"               # Pulsar dependencies version
pulsar_api_key: ""                         # Pulsar API key
```

### GCP Batch Configuration

```yaml
enable_gcp_batch: true                     # Auto-configure Galaxy for GCP Batch runner
gcp_batch_service_account_email: ""        # Service account email for Batch
gcp_batch_region: "us-east4"               # Region for GCP Batch
```

## Dependencies

This role has optional dependencies:

- `galaxyproject.cvmfs` - For CVMFS repository access (automatically installed when `setup_system: true`, can be disabled with `setup_cvmfs: false`)

## Example Playbooks

### Quick Start: Single-Node Galaxy Deployment

```yaml
---
- name: Deploy Galaxy on Kubernetes
  hosts: vms
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
        galaxy_values_files: ["values/my-galaxy-config.yml"]
        galaxy_bootstrap_api_key: "my-api-key"
```

### Deployment on Bare Ubuntu VMs

For fresh Ubuntu installations requiring full setup:

```yaml
---
- name: Deploy Galaxy on bare Ubuntu VM
  hosts: vms
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
        galaxy_values_files: ["values/my-galaxy-config.yml"]
        galaxy_bootstrap_api_key: "my-api-key"
```

### Pulsar Deployment

```yaml
---
- name: Deploy Pulsar for distributed job execution
  hosts: vms
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
3. Check values files: Ensure `galaxy_values_files` paths are correct
