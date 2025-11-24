# PR #0: Add GitHub workflow for automated Galaxy deployment testing on GCE

## Summary

This PR adds a GitHub Actions workflow that automatically deploys Galaxy to a GCE VM and verifies the deployment by testing the Galaxy API. This provides automated integration testing for the galaxy-k8s-boot project.

## Changes

### GitHub Workflow
- **File**: `.github/workflows/test-galaxy-gce.yml`
- **Trigger**: Manual (`workflow_dispatch`)
- **Authentication**: GCP Workload Identity Federation (keyless)
- **Cleanup**: Automatically deletes VM after testing (runs even on failure)

### Workflow Features

**Configurable Parameters:**
- `galaxy-chart-version` - Galaxy Helm chart version (default: 6.6.0)
- `git-repo` - Git repository URL for galaxy-k8s-boot
- `git-branch` - Git branch to deploy
- `instance-name` - Name for the test VM (default: galaxy-test-ci)
- `gcp-project` - GCP project ID
- `gcp-zone` - GCP zone

**Workflow Steps:**
1. Authenticates to GCP using Workload Identity
2. Generates SSH key pair for VM access
3. Launches GCE VM using `bin/launch_vm.sh`
4. Waits for cloud-init to complete
5. Copies kubeconfig from VM
6. Waits for all Galaxy deployments to rollout (15 minute timeout)
7. Tests `/api/version` endpoint and validates JSON response
8. Deletes VM (always runs, even on failure)
9. Displays test results summary

### Documentation
- **File**: `.github/workflows/README.md`
- Comprehensive setup instructions for GCP Workload Identity
- Step-by-step configuration guide
- Usage instructions and examples
- Troubleshooting tips

## Benefits

1. **Automated Testing**: Verify deployments work end-to-end before merging changes
2. **Cost Effective**: Uses keyless authentication (no service account keys to manage)
3. **Clean**: Automatically cleans up resources after testing
4. **Flexible**: Configurable parameters for different testing scenarios
5. **Reusable**: Can test any branch or fork with appropriate permissions

## Prerequisites

To use this workflow, repository administrators need to configure:

1. **GCP Workload Identity Pool and Provider** (can be shared across repositories)
2. **Service Account** with compute.instanceAdmin permissions
3. **GitHub Repository Secrets**:
   - `GCP_WORKLOAD_IDENTITY_PROVIDER`
   - `GCP_SERVICE_ACCOUNT`

Complete setup instructions are provided in `.github/workflows/README.md`.

## Security

- Uses Workload Identity Federation (no long-lived credentials)
- Service account has minimal required permissions
- Secrets are never exposed in logs
- VMs are always cleaned up (no orphaned resources)

## Testing

This workflow has been tested with:
- Multiple values files configurations
- Different chart versions
- Custom git repositories and branches
- Fork repositories (with appropriate IAM bindings)

## Files Added

- `.github/workflows/test-galaxy-gce.yml` - Main workflow definition
- `.github/workflows/README.md` - Setup and usage documentation

## Dependencies

This workflow depends on:
- `bin/launch_vm.sh` - VM launch script with parameter support
- RKE2 setup tasks that copy kubeconfig to `/home/ubuntu/.kube/config`
- GCP Workload Identity Federation configuration

## Future Enhancements

Potential future improvements:
- Matrix testing across multiple chart versions
- Integration with PR status checks
- Performance benchmarking
- Multi-region testing
- Slack/email notifications
