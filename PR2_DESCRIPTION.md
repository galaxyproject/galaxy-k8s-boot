# PR #2: Add support for multiple Helm values files

## Summary

This PR adds support for using multiple Helm values files when deploying Galaxy, enabling composable configuration patterns. It includes both Ansible role changes for direct playbook usage and command-line interface enhancements for VM launches.

## Changes

### Ansible Role Changes
- Update `galaxy_values_files` to accept a list of files
- Maintain backward compatibility with `galaxy_values_file` (single file, deprecated)
- Copy multiple values files to remote host with indexed filenames
- Pass all values files to Helm install using sequence lookup
- Add comprehensive documentation with usage examples
- Support composable configuration pattern

### VM Launch Script Changes
- Add `--galaxy-chart-version` parameter to specify Galaxy Helm chart version
- Add `--galaxy-deps-version` parameter to specify Galaxy dependencies chart version
- Add `-f|--values` parameter (can be specified multiple times) for Helm values files
- Order of values files is preserved (later files override earlier ones)
- Values are passed to VM via GCP instance metadata
- `user_data.sh` reads metadata and passes to `ansible-pull` as extra-vars
- Fix variable name bug in `user_data.sh` (PERSISTENT_DISK_SIZE → PV_SIZE)

## Benefits

This allows users to:
- Separate base configuration from environment-specific overrides
- Maintain common settings across deployments
- Add optional features (e.g., GCP Batch configuration) via additional values files
- Follow infrastructure-as-code best practices with modular configuration

## Backward Compatibility

The change is fully backward compatible:
- Existing playbooks using `galaxy_values_file` (string) continue to work
- New `galaxy_values_files` (list) variable is the recommended approach
- Falls back to `values/values.yml` if neither variable is specified

## Usage Examples

### Ansible Playbook Usage

#### Single file (backward compatible)
```bash
ansible-playbook -i inventory playbook.yml \
  --extra-vars "galaxy_values_file=values/custom.yml"
```

#### Multiple files
```bash
ansible-playbook -i inventory playbook.yml \
  -e galaxy_values_files='["values/base.yml","values/prod.yml","values/gcp-batch.yml"]'
```

### VM Launch Script Usage

#### Specify chart versions
```bash
bin/launch_vm.sh -k "ssh-rsa AAAAB3..." \
  --galaxy-chart-version "6.0.0" \
  --galaxy-deps-version "1.1.0" \
  my-galaxy-vm
```

#### Multiple values files (order matters - later files override earlier ones)
```bash
bin/launch_vm.sh -k "ssh-rsa AAAAB3..." \
  -f values/values.yml \
  -f values/gcp-batch.yml \
  my-galaxy-vm
```

#### Combined usage with long-form parameters
```bash
bin/launch_vm.sh -k "ssh-rsa AAAAB3..." \
  --galaxy-chart-version "6.0.0" \
  --values values/values.yml \
  --values values/dev.yml \
  --values values/v25.0.2.yml \
  my-test-vm
```

## Testing

### Ansible Role Testing
- Single values file using deprecated `galaxy_values_file`
- Multiple values files using `galaxy_values_files`
- Default behavior (no variables specified)

### VM Launch Script Testing
- Chart version parameters (--galaxy-chart-version, --galaxy-deps-version)
- Single values file with -f parameter
- Multiple values files with repeated -f/--values parameters
- Order preservation of values files (array → CSV → JSON → Ansible)
- Metadata passing from launch_vm.sh to user_data.sh
- Default behavior when no parameters specified

## Files Modified

### Ansible Role Files
- `roles/galaxy_k8s_deployment/defaults/main.yml` - Added galaxy_values_files list support
- `roles/galaxy_k8s_deployment/tasks/galaxy_application.yml` - Implemented multi-file handling
- `README.md` - Added "Advanced Configuration" section

### VM Launch Files
- `bin/launch_vm.sh` - Added chart version and values file parameters; fixed gcloud metadata passing
- `bin/user_data.sh` - Added metadata reading and ansible-pull parameter passing; fixed cloud-init quoting

## Documentation

Added comprehensive "Advanced Configuration" section to README.md with:
- Usage examples for single and multiple files
- Example composable configuration setup
- Best practices for organizing values files
- VM launch script parameter documentation and examples

## Troubleshooting and Fixes

During testing, several issues were identified and resolved:

### Issue #1: GCloud Metadata Delimiter Conflict
**Problem**: Using comma-separated values files conflicted with gcloud's metadata format
**Error**: `ERROR: (gcloud.compute.instances.create) argument --metadata: Bad syntax for dict arg`
**Initial Solution**: Changed delimiter from comma to semicolon

### Issue #2: Cloud-init Quoting Issue
**Problem**: Complex awk quoting with nested quotes broke inside cloud-init's bash -c command
**Error**: `bash: -c: line 15: unexpected EOF while looking for matching ')'`
**Solution**: Replaced awk with simpler sed command for JSON array conversion

### Issue #3: GCloud Metadata Multiple Parameters Error
**Problem**: GCloud doesn't support multiple `--metadata` flags
**Error**: `ERROR: (gcloud.compute.instances.create) argument --metadata: "metadata" argument cannot be specified multiple times`
**Final Solution**: Generate custom user_data.sh with values baked in instead of passing through metadata

### Issue #4: Ansible JSON Array Parsing
**Problem**: Values files were passed as string instead of JSON array to Ansible
**Error**: `Invalid data passed to 'loop', it requires a list, got this instead: [values/values.yml,...]`
**Solution**: Use proper JSON object format for entire `--extra-vars` parameter

## Final Implementation

The final solution generates a temporary user_data.sh script with all configuration values directly substituted:
- Avoids all metadata parameter passing complexity
- Eliminates special character escaping issues
- Makes the solution more portable across cloud providers
- Simplifies debugging (can inspect the generated script)
- Properly formats extra-vars as JSON object for Ansible
