# CNPG Skip-Initdb Plugin Integration

This document describes how to enable PostgreSQL data reuse when relaunching Galaxy instances with existing persistent disks.

## Overview

When relaunching a Galaxy instance that reuses persistent disks, two components need to work together:

1. **Storage Provisioner** - Must reuse existing data directories instead of creating new ones
2. **CNPG Plugin** - Must tell CloudNative-PG to skip database initialization and use existing data

Without both components, CNPG will attempt to initialize a new PostgreSQL cluster even if the storage contains existing data.

## Prerequisites

### 1. cert-manager

The CNPG plugin requires cert-manager for TLS certificate management. When using the Ansible playbook, cert-manager is installed automatically when `setup_cert_manager: true` is set.

For manual installation:
```bash
# Install cert-manager (use latest stable version)
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.0/cert-manager.yaml

# Wait for cert-manager to be ready
kubectl wait --for=condition=Available deployment/cert-manager -n cert-manager --timeout=300s
kubectl wait --for=condition=Available deployment/cert-manager-webhook -n cert-manager --timeout=300s
```

### 2. Plugin Container Image

The plugin image must be built and pushed to an accessible container registry.

The default image is available at `quay.io/galaxyproject/cnpg-i-skip-initdb:0.1`.

To build your own image:
```bash
# Clone the plugin repository (if not already done)
git clone https://github.com/CloudVE/cnpg-i-skip-initdb.git
cd cnpg-i-skip-initdb

# Build the image (use --platform for cross-platform builds on arm64 machines)
docker build --platform linux/amd64 -t quay.io/galaxyproject/cnpg-i-skip-initdb:0.1 .

# Push to registry (requires authentication)
docker push quay.io/galaxyproject/cnpg-i-skip-initdb:0.1
```

## Configuration

### Ansible Variables

The following variable controls Galaxy restoration behavior:

```yaml
# Galaxy Restoration Control
# Optional variable that controls restoration of both PVC and PostgreSQL database
# Values:
#   "" (empty/default) = Fresh installation with dynamic PVC provisioning
#   "auto"             = Auto-detect existing PVC UUID from NFS exports and restore
#   "<uuid>"           = Restore from specific PVC UUID (e.g., "57681430-eb8f-460f-9eae-294e061c579e")
galaxy_restore_pvc_uuid: ""

# CNPG plugin configuration (advanced - typically no need to change)
cnpg_skip_initdb_image: "quay.io/galaxyproject/cnpg-i-skip-initdb:0.1"
cnpg_skip_initdb_namespace: "galaxy-deps"
cnpg_skip_initdb_plugin_name: "cnpg-i-skip-initdb.leonardoce.github.com"
```

**Note:** The CNPG skip-initdb plugin is automatically deployed when restoration is enabled.
The plugin automatically detects existing PostgreSQL data and skips initialization if found.

### Example Deployment Commands

**Fresh installation** (default behavior):
```bash
ansible-playbook -i inventories/my-server.ini playbook.yml \
  --extra-vars "galaxy_user=admin@example.com"
```

**Relaunch with auto-detection** (automatically finds and restores existing data):
```bash
ansible-playbook -i inventories/my-server.ini playbook.yml \
  --extra-vars "galaxy_user=admin@example.com" \
  --extra-vars "galaxy_restore_pvc_uuid=auto"
```

**Relaunch with explicit UUID** (restore from specific PVC):
```bash
ansible-playbook -i inventories/my-server.ini playbook.yml \
  --extra-vars "galaxy_user=admin@example.com" \
  --extra-vars "galaxy_restore_pvc_uuid=57681430-eb8f-460f-9eae-294e061c579e"
```

### Using the VM Launch Script

When using the `bin/launch_vm.sh` script for GCP deployments:

**Fresh installation**:
```bash
bin/launch_vm.sh my-galaxy-vm
```

**Auto-detect and restore**:
```bash
bin/launch_vm.sh my-galaxy-vm --restore-galaxy
```

**Restore from specific UUID**:
```bash
bin/launch_vm.sh my-galaxy-vm --restore-pvc-uuid 57681430-eb8f-460f-9eae-294e061c579e
```

## How It Works

### Storage Provisioner Directory Reuse

The local-path-provisioner creates directories with the pattern:
```
/mnt/postgres_storage/pvc-<uuid>_<namespace>_<pvc-name>
```

The modified setup script in `templates/postgres_storage_class.yaml.j2`:

1. Extracts `<namespace>_<pvc-name>` from the new directory path
2. Searches for existing directories matching `pvc-*_<namespace>_<pvc-name>`
3. If found with data, creates a symlink to the existing directory
4. If not found, creates a new directory as normal

This ensures the new PVC points to existing PostgreSQL data.

### CNPG Plugin Behavior

The skip-initdb plugin is deployed automatically when restoration is enabled (`galaxy_restore_pvc_uuid` is set).
The plugin uses **auto-detection**:

1. Plugin deploys to `galaxy-deps` namespace (same as CNPG operator)
2. Registers with CNPG via service annotations
3. When CNPG attempts to create the initdb Job, the plugin intercepts it
4. Plugin checks if `$PGDATA` directory contains existing database files:
   - **If PGDATA has database files**: Plugin replaces the initdb Job with a no-op, allowing PostgreSQL to start with existing data
   - **If PGDATA is empty/missing**: Plugin allows normal initdb to proceed (graceful degradation)

**IMPORTANT**: The plugin MUST be deployed to the same namespace as the CNPG operator. In Galaxy deployments, the CNPG operator runs in the `galaxy-deps` namespace (installed by the galaxy-deps Helm chart). Deploying the plugin to a different namespace (like `cnpg-system`) will result in CNPG not discovering the plugin.

### Plugin Registration

The plugin is registered with CNPG through:

1. **Service annotations** that identify it to CNPG:
   ```yaml
   annotations:
     cnpg.io/pluginClientSecret: skip-initdb-client-tls
     cnpg.io/pluginServerSecret: skip-initdb-server-tls
     cnpg.io/pluginPort: "9090"
   labels:
     cnpg.io/pluginName: cnpg-i-skip-initdb.leonardoce.github.com
   ```

2. **Cluster spec** that references the plugin:
   ```yaml
   postgresql:
     cluster:
       plugins:
         - name: cnpg-i-skip-initdb.leonardoce.github.com
   ```

The plugin is automatically included in the cluster spec when restoration is enabled.

## Files Modified

| File | Purpose |
|------|---------|
| `templates/cnpg_skip_initdb_plugin.yaml.j2` | Plugin deployment template |
| `templates/postgres_storage_class.yaml.j2` | Storage provisioner with directory reuse |
| `templates/hostpath_storage_class.yaml.j2` | Blockstorage provisioner with directory reuse |
| `roles/galaxy_k8s_deployment/defaults/main.yml` | Default configuration variables |
| `roles/galaxy_k8s_deployment/tasks/storage_setup.yml` | cert-manager installation task |
| `roles/galaxy_k8s_deployment/tasks/galaxy_application.yml` | Plugin deployment, NFS reuse, RabbitMQ sync, and Helm values |

## Troubleshooting

### Check Plugin Deployment

```bash
# Verify plugin is running (in galaxy-deps namespace)
kubectl get pods -n galaxy-deps -l app=skip-initdb

# Check plugin logs
kubectl logs -n galaxy-deps -l app=skip-initdb

# Verify certificates are created
kubectl get certificates -n galaxy-deps
```

### Check Storage Symlinks

```bash
# SSH to the VM and check postgres storage
ls -la /mnt/postgres_storage/

# Verify symlink points to existing data
readlink /mnt/postgres_storage/pvc-<new-uuid>_galaxy_galaxy-postgres-1
```

### Check CNPG Cluster Status

```bash
# Get cluster status
kubectl get clusters.postgresql.cnpg.io -n galaxy

# Check if plugin is recognized
kubectl describe clusters.postgresql.cnpg.io galaxy-postgres -n galaxy | grep -A5 plugins
```

### Common Issues

1. **Plugin not found by CNPG**
   - **Most common cause**: Plugin deployed to wrong namespace. The plugin MUST be in `galaxy-deps` namespace (where CNPG operator runs), NOT in `cnpg-system` or other namespaces
   - Ensure cert-manager is running and certificates are created
   - Verify plugin pod is running: `kubectl get pods -n galaxy-deps -l app=skip-initdb`
   - Check CNPG operator logs for plugin discovery: `kubectl logs -n galaxy-deps -l app.kubernetes.io/name=cloudnative-pg`

2. **Plugin name mismatch**
   - The plugin reports itself as `cnpg-i-skip-initdb.leonardoce.github.com`
   - Ensure the Helm values and service label use this exact name
   - Check cluster configuration: `kubectl describe clusters.postgresql.cnpg.io -n galaxy | grep -A5 plugins`

3. **Storage not reusing existing data**
   - Check if old directory exists with correct suffix pattern
   - Verify provisioner ConfigMap has updated setup script
   - Check provisioner pod logs for symlink creation messages
   - Verify symlink was created: `ls -la /mnt/postgres_storage/`

4. **PostgreSQL fails to start**
   - Check PostgreSQL logs for permission issues
   - Verify data directory ownership matches expected user (typically postgres/26)
   - Ensure existing data is from compatible PostgreSQL version
   - Check for `pgdata_*` backup directories (indicates CNPG tried to reinitialize)

## Limitations

- The plugin requires CNPG version 1.24 or later
- cert-manager must be installed before enabling the plugin (unless using existing certificates)
- Plugin image must be accessible from the cluster
- Existing PostgreSQL data must be from a compatible version

## Using Existing Certificates Instead of cert-manager

The plugin uses mTLS for secure communication with CNPG. While the default implementation uses cert-manager to automatically generate certificates, you can use existing certificates instead.

### What the Plugin Needs

Two Kubernetes TLS secrets in the `galaxy-deps` namespace:

| Secret Name | Contents | Purpose |
|-------------|----------|---------|
| `skip-initdb-server-tls` | `tls.crt`, `tls.key` | Server certificate for plugin's gRPC server |
| `skip-initdb-client-tls` | `tls.crt`, `tls.key` | Client certificate for CNPG to authenticate to plugin |

### Changes Required to Use Existing Certificates

1. **Disable cert-manager installation** in your inventory or extra-vars:
   ```yaml
   setup_cert_manager: false
   ```

2. **Remove cert-manager resources from plugin template** - modify `templates/cnpg_skip_initdb_plugin.yaml.j2` to remove:
   - The `Issuer` resource (lines 14-20)
   - Both `Certificate` resources (lines 21-61)

3. **Create the secrets manually** before deploying Galaxy:
   ```bash
   # Generate self-signed certificates
   openssl genrsa -out ca.key 2048
   openssl req -x509 -new -nodes -key ca.key -days 365 -out ca.crt \
     -subj "/CN=skip-initdb-ca"

   # Server certificate (with SANs for service discovery)
   openssl genrsa -out server.key 2048
   cat > server.conf <<EOF
   [req]
   distinguished_name = req_distinguished_name
   req_extensions = v3_req
   [req_distinguished_name]
   CN = skip-initdb
   [v3_req]
   subjectAltName = @alt_names
   [alt_names]
   DNS.1 = skip-initdb
   DNS.2 = skip-initdb.galaxy-deps
   DNS.3 = skip-initdb.galaxy-deps.svc
   DNS.4 = skip-initdb.galaxy-deps.svc.cluster.local
   EOF
   openssl req -new -key server.key -out server.csr -config server.conf
   openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
     -out server.crt -days 365 -extensions v3_req -extfile server.conf

   # Client certificate
   openssl genrsa -out client.key 2048
   openssl req -new -key client.key -out client.csr \
     -subj "/CN=skip-initdb-client"
   openssl x509 -req -in client.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
     -out client.crt -days 365

   # Create Kubernetes secrets
   kubectl create namespace galaxy-deps --dry-run=client -o yaml | kubectl apply -f -
   kubectl create secret tls skip-initdb-server-tls \
     --cert=server.crt --key=server.key -n galaxy-deps
   kubectl create secret tls skip-initdb-client-tls \
     --cert=client.crt --key=client.key -n galaxy-deps
   ```

4. **Ensure secrets exist before Galaxy deployment** - the secrets must be created before running the Ansible playbook, or the plugin deployment will fail.

### Certificate Requirements

- **Server certificate** must include SANs (Subject Alternative Names) for the service DNS names
- **Both certificates** should be valid for at least as long as you plan to run the cluster
- **No automatic renewal** - you are responsible for rotating certificates before expiry

## Related Features

The CNPG skip-initdb plugin is part of a larger persistent data reuse solution. Other components include:

### NFS Export Reuse
When relaunching Galaxy instances, the NFS provisioner may report "insufficient space" even when existing data should be reused. The playbook automatically:
- Detects existing Galaxy NFS exports (by checking for `objects` subdirectory)
- Creates a static PV pointing to the existing export
- Binds the Galaxy PVC to the static PV

### RabbitMQ Credential Synchronization
When RabbitMQ data is preserved across relaunches, credential mismatches can occur. The playbook automatically:
- Checks if the expected RabbitMQ user exists
- Creates the user with administrator permissions if missing

### Configuration Variable

Galaxy restoration is controlled by a single variable:

```yaml
# Control all restoration behavior with one variable
galaxy_restore_pvc_uuid: ""
# Values:
#   "" (empty/default) = Fresh installation
#   "auto"             = Auto-detect and restore
#   "<uuid>"           = Restore from specific UUID
```

This variable controls:
- Galaxy PVC restoration (NFS data)
- PostgreSQL database restoration (CNPG plugin)
- RabbitMQ credential synchronization

When set to `"auto"` or a specific UUID, all persistent data features are automatically activated.

## References

- [CNPG-I Plugin Interface](https://github.com/cloudnative-pg/cnpg-i)
- [CloudNative-PG Documentation](https://cloudnative-pg.io/documentation/)
- [cert-manager Documentation](https://cert-manager.io/docs/)
- [Plugin Source Repository](https://github.com/CloudVE/cnpg-i-skip-initdb)
