# Galaxy Kubernetes Boot

Use this repo to deploy Galaxy. The repo contains Ansible playbooks to (1)
prepare a cloud image and (2) deploy a Galaxy instance. Galaxy is deployed on a
Kubernetes cluster using RKE2. The playbooks work on GCP, AWS, and OpenStack
(e.g., Jetstream2).

The deployed Galaxy can run jobs on the same K8s cluster but the intent of this
deployment model is for Galaxy to submit jobs to an external job management
system, such as GCP Batch.

## Overview

This repo is divided into two main playbooks:

1. **Image Preparation**: This part contains a playbook to prepare a cloud image
   with all necessary components pre-installed. See the [Image
   Preparation](roles/image_preparation/README.md) documentation for details.
2. **Deployment**: This part contains a playbook to deploy RKE2 Kubernetes
   cluster and Galaxy. Documentation for the deployment process can be found
   below.

## Deployment

The preferred way to deploy Galaxy is using a pre-built Debian 12 image
following the documentation below. The playbook can also run on a fresh Debian
12 VM, but it will take longer to complete as it needs to install all
dependencies. The playbook will install all necessary software by running an
Ansible playbook to deploy Galaxy. Galaxy should be available at
`http://INSTANCE_IP/` in about 6 minutes. The documentation below covers the
minimal steps using the `gcloud` command. For more options, see the [Advanced
Configuration](docs/advanced_configuration.md) documentation.

The most hands-off way to deploy Galaxy is to launch a VM on GCP so that it runs
the deployment playbook automatically on first boot. For this option, include
the `--metadata-from-file=user-data=bin/user_data.sh` option in the `gcloud`
command. One downside to this method is that it makes it difficult to rerun the
playbook, which can be useful during development. Instead, you can launch the VM
without user data and then run the Ansible playbook manually from your local
machine.

When deploying Galaxy, you can deploy a fresh instance or restore one from
existing persistent disks. By default, the playbook will create a fresh
installation. See documentation below for how to restore from existing data.

### Prerequisites

The default configuration will launch Galaxy configured to use GCP Batch for
running the workload. With that, you need to do the following initial set up to
configure use of Batch on the GCP side. Replace `anvil-and-terra-development` in
these commands with your project id. Note that this needs to set up only once
for a given account.

1. **GCP Service Account**: Create a service account with appropriate permissions:
   ```bash
   gcloud iam service-accounts create galaxy-batch-runner \
     --project=anvil-and-terra-development

   # Grant required permissions
   gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
     --member="serviceAccount:galaxy-batch-runner@anvil-and-terra-development.iam.gserviceaccount.com" \
     --role="roles/batch.jobsEditor"

   gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
     --member="serviceAccount:galaxy-batch-runner@anvil-and-terra-development.iam.gserviceaccount.com" \
     --role="roles/iam.serviceAccountUser"
   ```

2. **Firewall Rules**: Ensure GCP Batch VMs can access the NFS server:
   ```bash
   gcloud compute firewall-rules create allow-nfs-for-batch \
     --project=anvil-and-terra-development \
     --direction=INGRESS \
     --priority=1000 \
     --network=default \
     --action=ALLOW \
     --rules=tcp:2049,udp:2049,tcp:111,udp:111 \
     --source-ranges=10.0.0.0/8 \
     --target-tags=k8s
   ```

### Creating a Fresh VM

To create a VM instance but not run the playbook automatically, use the
following command. Update the metadata values as needed.

```bash
gcloud compute instances create ea-fresh \
  --project=anvil-and-terra-development \
  --zone=us-east4-c \
  --machine-type=e2-standard-4 \
  --image=galaxy-k8s-boot-v2026-06-30 \
  --image-project=anvil-and-terra-development \
  --boot-disk-size=100GB \
  --boot-disk-type=pd-balanced \
  --create-disk=name=galaxy-data-disk-1,size=150GB,type=pd-balanced,device-name=galaxy-data,auto-delete=no \
  --create-disk=name=galaxy-postgres-disk-1,size=10GB,type=pd-balanced,device-name=galaxy-postgres-data,auto-delete=no \
  --tags=k8s,http-server,https-server \
  --scopes=cloud-platform \
  --metadata=ssh-keys="debian:ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC66Snr9/0wpnzOkseCDm5xwq8zOI3EyEh0eec0MkED32ZBCFBcS1bnuwh8ZJtjgK0lDEfMAyR9ZwBlGM+BZW1j9h62gw6OyddTNjcKpFEdC9iA6VLpaVMjiEv9HgRw3CglxefYnEefG6j7RW4J9SU1RxEHwhUUPrhNv4whQe16kKaG6P6PNKH8tj8UCoHm3WdcJRXfRQEHkjoNpSAoYCcH3/534GnZrT892oyW2cfiz/0vXOeNkxp5uGZ0iss9XClxlM+eUYA/Klv/HV8YxP7lw8xWSGbTWqL7YkWa8qoQQPiV92qmJPriIC4dj+TuDsoMjbblcgMZN1En+1NEVMbV ea_key_pair",persistent-volume-size=139Gi,gcp_batch_service_account_email=galaxy-batch-runner@anvil-and-terra-development.iam.gserviceaccount.com
```

If you'd like to automatically run the playbook on first boot, include the
following option with the above `gcloud` command:

```bash
--metadata-from-file=user-data=bin/user_data.sh
```

**Note**: Both disks use `auto-delete=no` so the disks are retained after VM
deletion. You can toggle these if you want the disks to be automatically deleted
with the VM.

If you change the persistent disk size, review the following disk sizes in this
order:

1. the VM disk size (`--create-disk ... size=...GB`)
2. `persistent-volume-size` metadata variable
3. `nfs_size` in `defaults/main.yml`. If using `bin/user_data.sh`, it will set this so can skip.
4. `galaxy_persistence_size` in `defaults/main.yml`. If using `bin/user_data.sh`, it will set this so can skip.

On GCP, disk sizes are specified in GB while Kubernetes PVCs use Gi. So a
`150GB` disk is only about `139Gi` usable capacity for `nfs_size` and same for
`galaxy_persistence_size`.


### Restoring from Existing Data

If you kept the disks from a previous deployment, you can reattach them to a new
VM and restore the Galaxy instance from the existing data. To do this, use the
`--disk` flag instead of `--create-disk` when creating the VM:

```bash
--disk=name=existing-nfs-disk,device-name=galaxy-data,mode=rw \
--disk=name=existing-postgres-disk,device-name=galaxy-postgres-data,mode=rw \
```

If you are using the `--metadata-from-file=user-data=bin/user_data.sh` option to
run the playbook automatically, you will also need to include the
`restore_galaxy=true` metadata key to trigger the restoration process (if using
multiple metadata keys, separate them with commas):

```bash
--metadata=restore_galaxy=true
```

### Running the Playbook Manually

#### Prerequisites

Before you can run the playbook locally, we need to install the dependencies for
this repo.

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

#### Mounting Persistent Disks

Before running the playbook manually, you'll need to mount the persistent disks
on the VM and then run the playbook from your local machine. To mount the disks,
SSH into the VM and run the following commands:

**Note**: Skip the `mkfs.ext4` commands if reattaching existing disks with data.

```bash
# Mount NFS disk
sudo mkfs.ext4 /dev/disk/by-id/google-galaxy-data
sudo mount /dev/disk/by-id/google-galaxy-data /mnt/block_storage

# Mount PostgreSQL disk
sudo mkfs.ext4 /dev/disk/by-id/google-galaxy-postgres-data
sudo mount /dev/disk/by-id/google-galaxy-postgres-data /mnt/postgres_storage
```

#### Running the Playbook

Once the disks are mounted, run the playbook from your local machine. Start by
creating an inventory file for the VM:

```bash
bin/inventory.sh --name gcp --key my-key.pem --ip 11.22.33.44 > inventories/vm.ini
```

Then run the playbook. Check out the [examples](command_examples.md) for
different ways to run the playbook.

```bash
ansible-playbook -i inventories/vm.ini playbook.yml
```

If reattaching existing disks and restoring Galaxy data, include the restoration
variable (see [docs/CNPG_database_restore.md](docs/CNPG_database_restore.md)):

```bash
# Auto-detect existing data
--extra-vars "restore_galaxy=true"
```

Galaxy will be available at `http://INSTANCE_IP/` once deployment completes
(typically ~6 minutes).

## Deleting the VM

Uninstall the Galaxy Helm chart and cleanup Ansible-managed resources:

```bash
helm uninstall -n galaxy galaxy --wait
helm uninstall -n galaxy-deps galaxy-deps --wait

# Remove CNPG plugin if it was deployed (it's deployed by Ansible, not Helm)
kubectl delete deployment -n galaxy-deps -l app.kubernetes.io/part-of=galaxy --ignore-not-found=true
kubectl delete service -n galaxy-deps -l app.kubernetes.io/part-of=galaxy --ignore-not-found=true
kubectl delete certificate,issuer -n galaxy-deps -l app.kubernetes.io/part-of=galaxy --ignore-not-found=true
```

Optionally, you can also remove any symlinks left on the persistent disks:

```bash
# Clean up orphaned symlinks on persistent disks
sudo find /mnt/block_storage /mnt/postgres_storage -maxdepth 1 -type l -delete
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
