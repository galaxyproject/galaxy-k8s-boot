# GitHub Workflows

## Test Galaxy Deployment on GCE

The `test-galaxy-gce.yml` workflow deploys Galaxy to a GCE VM and tests that the API is responsive.

### Setup Requirements

This workflow uses GCP Workload Identity Federation for authentication. You need to configure the following:

#### 1. Create a Workload Identity Pool and Provider

```bash
# Set your project ID
PROJECT_ID="your-project-id"
PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format='value(projectNumber)')

# Create Workload Identity Pool
gcloud iam workload-identity-pools create "github-actions" \
  --project="${PROJECT_ID}" \
  --location="global" \
  --display-name="GitHub Actions Pool"

# Create Workload Identity Provider
gcloud iam workload-identity-pools providers create-oidc "github-provider" \
  --project="${PROJECT_ID}" \
  --location="global" \
  --workload-identity-pool="github-actions" \
  --display-name="GitHub Provider" \
  --attribute-mapping="google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.repository=assertion.repository" \
  --issuer-uri="https://token.actions.githubusercontent.com"
```

#### 2. Create a Service Account

```bash
# Create service account
gcloud iam service-accounts create github-actions-galaxy \
  --project="${PROJECT_ID}" \
  --display-name="GitHub Actions for Galaxy Testing"

# Grant necessary permissions
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:github-actions-galaxy@${PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/compute.instanceAdmin.v1"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:github-actions-galaxy@${PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/iam.serviceAccountUser"
```

#### 3. Configure Workload Identity Binding

```bash
# Replace with your GitHub repository
REPO="your-github-org/galaxy-k8s-boot"

# Allow GitHub Actions from your repository to impersonate the service account
gcloud iam service-accounts add-iam-policy-binding \
  "github-actions-galaxy@${PROJECT_ID}.iam.gserviceaccount.com" \
  --project="${PROJECT_ID}" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/github-actions/attribute.repository/${REPO}"
```

#### 4. Get the Workload Identity Provider Name

```bash
gcloud iam workload-identity-pools providers describe "github-provider" \
  --project="${PROJECT_ID}" \
  --location="global" \
  --workload-identity-pool="github-actions" \
  --format="value(name)"
```

This will output something like:
```
projects/123456789/locations/global/workloadIdentityPools/github-actions/providers/github-provider
```

#### 5. Configure GitHub Secrets

Add the following secrets to your GitHub repository:

- `GCP_WORKLOAD_IDENTITY_PROVIDER`: The full provider name from step 4
- `GCP_SERVICE_ACCOUNT`: The service account email (e.g., `github-actions-galaxy@PROJECT_ID.iam.gserviceaccount.com`)

### Running the Workflow

1. Go to Actions tab in your GitHub repository
2. Select "Test Galaxy Deployment on GCE" workflow
3. Click "Run workflow"
4. Customize parameters as needed:
   - **galaxy-chart-version**: Galaxy Helm chart version (default: 6.6.0)
   - **git-repo**: Repository URL for galaxy-k8s-boot
   - **git-branch**: Branch to deploy
   - **instance-name**: Name for the test VM
   - **gcp-project**: GCP project ID
   - **gcp-zone**: GCP zone

### What the Workflow Does

1. Authenticates to GCP using Workload Identity
2. Generates an SSH key pair for the VM
3. Launches a GCE VM using `bin/launch_vm.sh`
4. Waits for cloud-init to complete
5. Copies the kubeconfig from the VM
6. Waits for all Galaxy deployments to rollout (15 minute timeout)
7. Tests the `/api/version` endpoint
8. Validates the response is valid JSON
9. Deletes the VM (always runs, even on failure)

### Troubleshooting

If the workflow fails:
- Check the workflow logs for detailed error messages
- Verify Workload Identity is configured correctly
- Ensure the service account has necessary permissions
- Check GCP quotas for compute instances
