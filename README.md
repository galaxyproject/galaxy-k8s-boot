# Galaxy Kubernetes Boot

Use this repo to deploy Galaxy. The repo contains Ansible playbooks to prepare a
cloud image and deploy a Galaxy instance. Galaxy is deployed on a Kubernetes
cluster using RKE2. The playbooks work on GCP, AWS, and OpenStack (e.g.,
Jetstream2).

The deployed Galaxy can run jobs on the same K8s cluster but the intent of this
deployment model is for Galaxy to submit jobs to an external job management
system, such as GCP Batch.

## Overview

This repo is divided into two main parts:

1. **Image Preparation**: This part contains a playbook to prepare a cloud image
   with all necessary components pre-installed. See the [Image
   Preparation](roles/image_preparation/README.md) documentation for details.
2. **Deployment**: This part contains a playbook to deploy RKE2 Kubernetes
   cluster and Galaxy. Documentation for the deployment process can be found
   below.

## Deployment

The preferred way to deploy Galaxy is with a pre-built Ubuntu 24.04 image
following the documentation below. The playbook can also run on a fresh Ubuntu
24.04 VM, but it will take longer to complete as it needs to install all
dependencies. The documentation below covers the minimal steps. For more
options, see the [Advanced Configuration](docs/advanced_configuration.md)
documentation.

### Automated Deployment Directly on GCP

The most hands-off way to deploy Galaxy is to launch a VM on GCP that runs the
deployment playbook automatically on first boot. For this option, paste the
contents of `bin/launch_vm.sh` into the VM user data when launching the
instance. This will install all necessary software by running an Ansible
playbook to deploy Galaxy. Galaxy should be available at `http://INSTANCE_IP/`
in about 6 minutes.

#### Monitoring Deployment

After launching the VM, you can ssh into the VM to monitor the deployment
progress:

```bash
# Watch cloud-init output
sudo tail -n +1 -f /var/log/cloud-init-output.log

# Monitor deployment logs
sudo journalctl -f -u cloud-final
```

### Deployment from Local Machine

One downside to the above method is that it makes it difficult to customize the
deployment or rerun the playbook, which is useful during development. Instead,
you can launch the VM without user data and then run the Ansible playbook from
your local machine.

> [!NOTE]
> There is also `bin/launch_vm.sh` script that automates the steps for launching
> the VM and running the playbook. This is often useful for scenarios where you
> want to test Galaxy functionality or configuration changes. Check out
> `bin/launch_vm.sh --help` for details.

#### Prerequisites

To run the playbook locally, we need to install the dependencies for this repo.

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

#### Creating a VM

Use the `gcloud` command to create a VM instance.

```bash
gcloud compute instances create ea-fresh \
  --project=anvil-and-terra-development \
  --zone=us-east4-c \
  --machine-type=e2-standard-8 \
  --image=galaxy-k8s-boot-v2025-11-14 \
  --image-project=anvil-and-terra-development \
  --boot-disk-size=100GB \
  --boot-disk-type=pd-balanced \
  --create-disk=name=galaxy-data-disk-1,size=150GB,type=pd-balanced,device-name=galaxy-data,auto-delete=no \
  --create-disk=name=galaxy-postgres-disk-1,size=10GB,type=pd-balanced,device-name=galaxy-postgres-data,auto-delete=no \
  --tags=k8s,http-server,https-server \
  --scopes=cloud-platform \
  --metadata=ssh-keys="ubuntu:ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC66Snr9/0wpnzOkseCDm5xwq8zOI3EyEh0eec0MkED32ZBCFBcS1bnuwh8ZJtjgK0lDEfMAyR9ZwBlGM+BZW1j9h62gw6OyddTNjcKpFEdC9iA6VLpaVMjiEv9HgRw3CglxefYnEefG6j7RW4J9SU1RxEHwhUUPrhNv4whQe16kKaG6P6PNKH8tj8UCoHm3WdcJRXfRQEHkjoNpSAoYCcH3/534GnZrT892oyW2cfiz/0vXOeNkxp5uGZ0iss9XClxlM+eUYA/Klv/HV8YxP7lw8xWSGbTWqL7YkWa8qoQQPiV92qmJPriIC4dj+TuDsoMjbblcgMZN1En+1NEVMbV ea_key_pair"
```

**Note**: Both disks use `auto-delete=no` to persist after VM deletion.

For attaching existing disks instead of `--create-disk` options, use multiple
`--disk` flags:
```bash
--disk=name=existing-nfs-disk,device-name=galaxy-data,mode=rw \
--disk=name=existing-postgres-disk,device-name=galaxy-postgres-data,mode=rw \
```

> [!CAUTION]
> **Note:** Reattaching existing disks preserves the data on disk, but CNPG will
> create a new PostgreSQL cluster each time this playbook is run, effectively
> resulting in a new, empty Galaxy instance. CNPG recovery/restore functionality
> will be addressed in future releases.

If you'd like to replicate the automated deployment, add the following option to
the `gcloud` command:

```bash
--metadata-from-file=user-data=bin/user_data.sh
```

#### Mounting Persistent Disks

Before running the Ansible playbook, SSH into the VM and mount the attached
persistent disks:

**Note**: Skip the `mkfs.ext4` commands if reattaching existing disks with data.

```bash
# Mount NFS disk
sudo mkdir -p /mnt/block_storage
sudo mkfs.ext4 /dev/disk/by-id/google-galaxy-data
sudo mount /dev/disk/by-id/google-galaxy-data /mnt/block_storage

# Mount PostgreSQL disk
sudo mkdir -p /mnt/postgres_storage
sudo mkfs.ext4 /dev/disk/by-id/google-galaxy-postgres-data
sudo mount /dev/disk/by-id/google-galaxy-postgres-data /mnt/postgres_storage
```

#### Running the Playbook

Once the disks are mounted, run the playbook from your local machine. Start by
creating an inventory file for the VM:

```bash
bin/inventory.sh --name gcp --key my-key.pem --ip 11.22.33.44 > inventories/vm.ini
```

Then run the playbook. Check out the [examples](command_examples.md) for different
ways to run the playbook.

```bash
ansible-playbook -i inventories/vm.ini playbook.yml --extra-vars "galaxy_user=admin@email.com"
```

If reattaching existing disks and restoring Galaxy data, include the restoration
variable (see [docs/CNPG_database_restore.md](docs/CNPG_database_restore.md)):

```bash
# Auto-detect existing data
--extra-vars "galaxy_restore_pvc_uuid=auto"
```

Galaxy will be available at `http://INSTANCE_IP/` once deployment completes
(typically ~6 minutes).

### GCP Batch Job Runner

The Galaxy deployment can be configured to use Google Cloud Batch for job execution, allowing Galaxy to scale job processing independently of the Kubernetes cluster.

#### Prerequisites

1. **GCP Service Account**: Create a service account with appropriate permissions:
   ```bash
   gcloud iam service-accounts create galaxy-batch-runner \
     --project=YOUR_PROJECT_ID

   # Grant required permissions
   gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
     --member="serviceAccount:galaxy-batch-runner@YOUR_PROJECT_ID.iam.gserviceaccount.com" \
     --role="roles/batch.jobsEditor"

   gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
     --member="serviceAccount:galaxy-batch-runner@YOUR_PROJECT_ID.iam.gserviceaccount.com" \
     --role="roles/iam.serviceAccountUser"
   ```

2. **Firewall Rules**: Ensure GCP Batch VMs can access the NFS server:
   ```bash
   gcloud compute firewall-rules create allow-nfs-for-batch \
     --project=YOUR_PROJECT_ID \
     --direction=INGRESS \
     --priority=1000 \
     --network=default \
     --action=ALLOW \
     --rules=tcp:2049,udp:2049,tcp:111,udp:111 \
     --source-ranges=10.0.0.0/8 \
     --target-tags=k8s
   ```

3. **Kubernetes Secret**: Create a secret with the service account key:
   ```bash
   kubectl create secret generic gcp-batch-key \
     --from-file=key.json=/path/to/service-account-key.json \
     --namespace galaxy
   ```

#### Deployment

Deploy Galaxy with GCP Batch enabled:

```bash
ansible-playbook -i inventories/vm.ini playbook.yml \
  --extra-vars "enable_gcp_batch=true" \
  --extra-vars "gcp_batch_service_account_email=galaxy-batch-runner@YOUR_PROJECT_ID.iam.gserviceaccount.com" \
  --extra-vars "gcp_batch_region=us-east4"
```

Or combine with multiple values files:

```bash
ansible-playbook -i inventories/vm.ini playbook.yml \
  -e enable_gcp_batch=true \
  -e gcp_batch_service_account_email=galaxy-batch-runner@YOUR_PROJECT_ID.iam.gserviceaccount.com \
  -e galaxy_values_files='["values/values.yml","values/gcp-batch.yml"]'
```

#### What Gets Configured Automatically

When `enable_gcp_batch=true`, the playbook automatically:
- **Detects NFS LoadBalancer IP**: Configures internal LoadBalancer for NFS with source IP restrictions
- **Detects NFS Export Path**: Automatically finds the Galaxy PVC export path using `showmount`
- **Updates job_conf.yml**: Injects NFS server IP and export path into GCP Batch runner configuration
- **Restarts Deployments**: Applies configuration changes by restarting Galaxy pods

No manual intervention required for NFS path detection or configuration updates.

## Deleting the VM

Before deleting the VM, if you will want to preserve the Galaxy data, record the
PVC UUID for Galaxy. You can use the following command to get the UUID:

```bash
kubectl get pv -o jsonpath='{range .items[?(@.spec.claimRef.name=="galaxy-galaxy-pvc")]}{.metadata.name}{"\n"}{end}'

# Example output: pvc-57681430-eb8f-460f-9eae-294e061c579e
# Record the UUID part: 57681430-eb8f-460f-9eae-294e061c579e
```

Uninstall the Galaxy Helm chart to ensure all resources are properly cleaned up:

```bash
helm uninstall -n galaxy galaxy --wait
helm uninstall -n galaxy-deps galaxy-deps --wait
```
Then, delete the VM using:

```bash
gcloud compute instances delete INSTANCE_NAME --zone=us-east4-c [--quiet]
```

## Installing Pulsar

The playbook can set up a Pulsar node instead of Galaxy. The invocation process is the same with the only difference being the `application` variable.

```bash
ansible-playbook -i inventories/vm.ini playbook.yml --extra-vars "application=pulsar" --extra-vars "pulsar_api_key=changeme"
```
