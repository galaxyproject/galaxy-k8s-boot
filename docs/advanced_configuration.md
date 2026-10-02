# Advanced Configuration

## Managing the Kubernetes cluster

If you would like to manage the Kubernetes cluster, you can use the `kubectl` command on the server, or download the `kubeconfig` file from the server and use it on your local machine. The playbook copies the RKE2 kubeconfig to the VM user's home directory (default user `debian`).

```bash
scp -i my-key.pem debian@<server-ip>:/home/debian/.kube/config ~/.kube/config
```

The kubeconfig points at `127.0.0.1`, so update the `server:` address to the VM's IP after downloading it.

## Using Multiple Helm Values Files

The Galaxy deployment supports using multiple Helm values files, which allows you to compose configurations from different sources. This is useful for:
- Separating base configuration from environment-specific overrides
- Maintaining common settings across deployments
- Adding optional features (like GCP Batch) via additional values files

### Single Values File (Default)

By default, the playbook uses `values/values.yml`:

```bash
ansible-playbook -i inventories/vm.ini playbook.yml
```

You can specify a different single file:

```bash
ansible-playbook -i inventories/vm.ini playbook.yml \
  --extra-vars '{"galaxy_values_files": ["values/custom.yml"]}'
```

### Multiple Values Files

To use multiple values files, pass a list to `galaxy_values_files`:

```bash
ansible-playbook -i inventories/vm.ini playbook.yml \
  --extra-vars '{"galaxy_values_files": ["values/values.yml", "values/gcp-batch.yml"]}'
```

Or using JSON syntax:

```bash
ansible-playbook -i inventories/vm.ini playbook.yml \
  -e galaxy_values_files='["values/base.yml","values/prod.yml"]'
```

Files are applied in order, with later files overriding earlier ones (following Helm's standard behavior).

#### Example: Composing Configurations

Create separate values files for different purposes:

```yaml
# values/base.yml - Common settings
persistence:
  size: "20Gi"
postgresql:
  galaxyDatabasePassword: "changeme"

# values/production.yml - Production-specific settings
persistence:
  size: "100Gi"
configs:
  galaxy.yml:
    galaxy:
      admin_users: "admin@example.com"

# values/gcp-batch.yml - GCP Batch job runner
configs:
  job_conf.yml:
    runners:
      gcp_batch:
        load: galaxy.jobs.runners.gcp_batch:GoogleCloudBatchJobRunner
```

Then deploy with:

```bash
ansible-playbook -i inventories/vm.ini playbook.yml \
  -e galaxy_values_files='["values/base.yml","values/production.yml","values/gcp-batch.yml"]'
```

## User-Defined Tools

The default AnVIL values enable Galaxy's beta tool formats and allow user-defined
tools (UDTs) on the existing Kubernetes and GCP Batch destinations. TPV 3.2.1 or
newer is required; jobs retain the usual resource-based routing and must run in
containers. This configuration assumes AnVIL's single-user deployment model.

After Galaxy starts, the playbook grants `galaxy_user` a role of type
`user_tool_execute` (shown as **Custom Tool Execution** in the admin interface).
It skips the grant when the user already has an active execution role and runs on
fresh installations, upgrades, and restores independently of post-install imports
and quota setup. Multiuser instances do not receive an automatic grant.

Set `galaxy_grant_user_defined_tool_permissions=false` to manage permissions
manually. To disable the feature itself, override
`configs.galaxy.yml.galaxy.enable_beta_tool_formats` to `false` in a later values
file. Disabling automatic grants does not revoke an existing role.

## Rainstone Cost Reports

Rainstone is deployed with Galaxy by default. See [rainstone.md](rainstone.md)
for what the playbook configures and the variables that change it.
