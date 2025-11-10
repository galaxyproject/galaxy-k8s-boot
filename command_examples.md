# Example Reference Guide

## Common Deployment Scenarios

### 1. Full Galaxy Deployment on Bare VM (Single-Node)

```bash
ansible-playbook -i inventory playbook.yml \
  -e "rke2_token=my-secure-token" \
  -e "chart_values_file=values/values.yml" \
  -e "galaxy_api_key=my-api-key"
```

### playbook.yml

Unified deployment playbook optimized for pre-prepared images:

```bash
# Pre-prepared image deployment (default)
ansible-playbook -i inventories/vm.ini playbook.yml \
  -e "chart_values_file=values.yml" \
  -e "rke2_token=my-secure-token"

# Bare Ubuntu VM deployment (full setup)
ansible-playbook -i inventories/vm.ini playbook.yml \
  -e "setup_system=true" \
  -e "application=galaxy" \
  -e "chart_values_file=values/values.yml" \
  -e "galaxy_api_key=my-api-key"
```

### 3. Infrastructure Only (No Applications)

```bash
ansible-playbook -i inventories/vm.ini playbook.yml \
  -e "deploy_galaxy=false" \
  -e "rke2_token=my-secure-token"
```

### 4. Pulsar Deployment

```bash
ansible-playbook -i inventories/vm.ini playbook.yml \
  -e "application=pulsar" \
  -e "pulsar_api_key=my-pulsar-key"
```

## Key Variables

### Required Variables

```yaml
rke2_token: "your-cluster-token"          # Always required for RKE2
```

### Commonly Overridden Variables

```yaml
# Galaxy Configuration
galaxy_values_file: "values/custom.yml"   # Path to your values file
galaxy_api_key: "your-api-key"            # Galaxy master API key
galaxy_user: "admin@galaxy.org"           # Admin user email
galaxy_persistence_size: "50Gi"           # Data volume size

# RKE2 Configuration
rke2_additional_sans:                     # Additional domain names
  - galaxy.example.com
  - *.example.com

# NFS Storage
nfs_size: "25Gi"                          # NFS backing storage size
nfs_default: true                         # Make NFS default storage class
```

## Useful Commands

### Check Deployment Status

```bash
# Check all pods
kubectl get pods -A

# Check Galaxy specifically
kubectl get pods -n galaxy

# Check storage
kubectl get pvc -A
kubectl get storageclass

# Check ingress
kubectl get ingress -A
```

### View Logs

```bash
# Galaxy web pod
kubectl logs -n galaxy -l app.kubernetes.io/name=galaxy,app.kubernetes.io/component=galaxy-web

# RKE2 server
journalctl -u rke2-server -f

# Ingress controller
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx
```

### Helm Operations

```bash
# List releases
helm list -A

# Check Galaxy release
helm status galaxy -n galaxy

# Get values
helm get values galaxy -n galaxy
```

## Troubleshooting

### RKE2 Won't Start

```bash
# Check service status
systemctl status rke2-server

# View logs
journalctl -u rke2-server -n 100

# Verify config
cat /etc/rancher/rke2/config.yaml
```

### Storage Issues

```bash
# Check storage classes
kubectl get storageclass

# Check NFS provisioner
kubectl get pods -n nfs-provisioner
kubectl logs -n nfs-provisioner -l app=nfs-server-provisioner

# Check PVCs
kubectl get pvc -A
kubectl describe pvc <pvc-name> -n <namespace>
```

### Galaxy Won't Start

```bash
# Check all Galaxy pods
kubectl get pods -n galaxy

# Check specific pod
kubectl describe pod <pod-name> -n galaxy
kubectl logs <pod-name> -n galaxy

# Check Helm release
helm status galaxy -n galaxy
helm get values galaxy -n galaxy
```

## Role Task Control

Enable/disable specific components:

```yaml
# In your playbook or variables file
setup_system: true      # System packages
setup_rke2: true        # RKE2 cluster
setup_helm: true        # Helm installation
setup_nfs: true         # NFS provisioner
setup_storage: true     # Storage classes
setup_ingress: true     # Ingress controller
deploy_galaxy: true     # Galaxy application
deploy_pulsar: false    # Pulsar application
```

## File Locations

### Configuration Files

```
/etc/rancher/rke2/config.yaml                    # RKE2 configuration
/etc/rancher/rke2/rke2.yaml                      # Kubeconfig
```

### Role Files

```
roles/galaxy_k8s_deployment/
  defaults/main.yml                              # Default variables
  tasks/main.yml                                 # Main orchestrator
  README.md                                      # Detailed documentation
```

### Values Files

```
values/
  values.yml                                     # Default Galaxy values
  [your-custom].yml                              # Your custom values
```
