#!/bin/bash

# Galaxy Kubernetes Boot VM Launch Script
# This script handles VM creation with automatic persistent disk management

set -e

# Default values
PROJECT="anvil-and-terra-development"
ZONE="us-east4-c"
MACHINE_TYPE="e2-standard-4"
MACHINE_IMAGE="galaxy-k8s-boot-v2025-11-14"
BOOT_DISK_SIZE="100GB"
DISK_SIZE="150GB"
DISK_TYPE="pd-balanced"
GIT_REPO="https://github.com/galaxyproject/galaxy-k8s-boot.git"
GIT_BRANCH="master"
GALAXY_CHART_VERSION="6.6.0"
GALAXY_DEPS_VERSION="1.1.1"

# Parse command line arguments
INSTANCE_NAME=""
DISK_NAME=""
SSH_KEY=""
EPHEMERAL_ONLY=false
GALAXY_VALUES_FILES=()  # Array to hold multiple values files

usage() {
    cat << EOF
Usage: $0 [OPTIONS] INSTANCE_NAME

Launch a Galaxy Kubernetes VM with automatic persistent disk management.

Required Arguments:
  INSTANCE_NAME       Name of the VM instance to create

Options:
  -p, --project PROJECT              GCP project ID (default: $PROJECT)
  -z, --zone ZONE                   GCP zone (default: $ZONE)
  -i, --machine-image IMAGE         Machine image name (default: $MACHINE_IMAGE)
  -d, --disk-name DISK_NAME         Name of persistent disk (default: galaxy-data-INSTANCE_NAME)
  -s, --disk-size SIZE              Size of persistent disk (default: $DISK_SIZE)
  -k, --ssh-key SSH_KEY             SSH public key for ubuntu user (required)
  -m, --machine-type TYPE           Machine type (default: $MACHINE_TYPE)
  -g, --git-repo REPO               Git repository URL (default: $GIT_REPO)
  -b, --git-branch BRANCH           Git branch to deploy (default: $GIT_BRANCH)
  --galaxy-chart-version VERSION    Galaxy Helm chart version (default: $GALAXY_CHART_VERSION)
  --galaxy-deps-version VERSION     Galaxy dependencies chart version (default: $GALAXY_DEPS_VERSION)
  -f, --values FILE                 Helm values file (can be specified multiple times, default: values/values.yml)
  --ephemeral-only                  Create VM without persistent disk
  -h, --help                        Show this help message

Examples:
  # Launch VM with new or existing disk
  $0 -k "ssh-rsa AAAAB3..." my-galaxy-vm

  # Launch VM with specific machine image
  $0 -k "ssh-rsa AAAAB3..." -i galaxy-k8s-boot-v2025-11-14 my-galaxy-vm

  # Launch VM with specific disk name
  $0 -k "ssh-rsa AAAAB3..." -d galaxy-shared-disk my-galaxy-vm

  # Create VM without persistent storage (testing only)
  $0 -k "ssh-rsa AAAAB3..." --ephemeral-only my-galaxy-vm

  # Launch VM with custom git repository and branch
  $0 -k "ssh-rsa AAAAB3..." -g "https://github.com/username/galaxy-k8s-boot.git" -b "feature-branch" my-galaxy-vm

  # Launch VM with specific Galaxy chart versions
  $0 -k "ssh-rsa AAAAB3..." --galaxy-chart-version "6.0.0" --galaxy-deps-version "1.1.0" my-galaxy-vm

  # Launch VM with multiple Helm values files (order matters - later files override earlier ones)
  $0 -k "ssh-rsa AAAAB3..." -f values/values.yml -f values/gcp-batch.yml my-galaxy-vm
  $0 -k "ssh-rsa AAAAB3..." --values values/values.yml --values values/dev.yml --values values/v25.0.2.yml my-galaxy-vm

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--project)
            PROJECT="$2"
            shift 2
            ;;
        -z|--zone)
            ZONE="$2"
            shift 2
            ;;
        -i|--machine-image)
            MACHINE_IMAGE="$2"
            shift 2
            ;;
        -d|--disk-name)
            DISK_NAME="$2"
            shift 2
            ;;
        -s|--disk-size)
            DISK_SIZE="$2"
            shift 2
            ;;
        -k|--ssh-key)
            SSH_KEY="$2"
            shift 2
            ;;
        -m|--machine-type)
            MACHINE_TYPE="$2"
            shift 2
            ;;
        -g|--git-repo)
            GIT_REPO="$2"
            shift 2
            ;;
        -b|--git-branch)
            GIT_BRANCH="$2"
            shift 2
            ;;
        --galaxy-chart-version)
            GALAXY_CHART_VERSION="$2"
            shift 2
            ;;
        --galaxy-deps-version)
            GALAXY_DEPS_VERSION="$2"
            shift 2
            ;;
        -f|--values)
            GALAXY_VALUES_FILES+=("$2")
            shift 2
            ;;
        --ephemeral-only)
            EPHEMERAL_ONLY=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -*)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
        *)
            if [ -z "$INSTANCE_NAME" ]; then
                INSTANCE_NAME="$1"
            else
                echo "Error: Multiple instance names provided"
                usage
                exit 1
            fi
            shift
            ;;
    esac
done

# Validate required arguments
if [ -z "$INSTANCE_NAME" ]; then
    echo "Error: Instance name is required"
    usage
    exit 1
fi

if [ "$EPHEMERAL_ONLY" = false ] && [ -z "$SSH_KEY" ]; then
    echo "Error: SSH key is required"
    usage
    exit 1
fi

# Set default disk name if not provided
if [ -z "$DISK_NAME" ]; then
    DISK_NAME="galaxy-data-$INSTANCE_NAME"
fi

# Set default values file if none provided
if [ ${#GALAXY_VALUES_FILES[@]} -eq 0 ]; then
    GALAXY_VALUES_FILES=("values/values.yml")
fi

# Convert values files array to semicolon-separated string for metadata
# (semicolon is used instead of comma to avoid conflicts with gcloud metadata format)
GALAXY_VALUES_FILES_LIST=$(IFS=';'; echo "${GALAXY_VALUES_FILES[*]}")

echo "=== Galaxy Kubernetes Boot VM Launch ==="
echo "Instance Name: $INSTANCE_NAME"
echo "Project: $PROJECT"
echo "Zone: $ZONE"
echo "Machine Type: $MACHINE_TYPE"
echo "Machine Image: $MACHINE_IMAGE"
echo "Git Repository: $GIT_REPO"
echo "Git Branch: $GIT_BRANCH"
echo "Galaxy Chart Version: $GALAXY_CHART_VERSION"
echo "Galaxy Deps Version: $GALAXY_DEPS_VERSION"
echo "Galaxy Values Files: ${GALAXY_VALUES_FILES[@]}"

if [ "$EPHEMERAL_ONLY" = false ]; then
    echo "Disk Name: $DISK_NAME"
    echo "Disk Size: $DISK_SIZE"
fi

echo ""

# Handle disk management
DISK_FLAG=""
if [ "$EPHEMERAL_ONLY" = false ]; then
    # Check if disk exists
    if gcloud compute disks describe "$DISK_NAME" --project="$PROJECT" --zone="$ZONE" &>/dev/null; then
        echo "✓ Disk '$DISK_NAME' already exists, will attach existing disk."
        DISK_FLAG="--disk=name=$DISK_NAME,device-name=galaxy-data,mode=rw"

        # Get existing disk size
        EXISTING_DISK_SIZE=$(gcloud compute disks describe "$DISK_NAME" --project="$PROJECT" --zone="$ZONE" --format='get(sizeGb)')
        DISK_SIZE_GB="$EXISTING_DISK_SIZE"
    else
        echo "ℹ Disk '$DISK_NAME' does not exist, will create new disk ($DISK_SIZE)."
        DISK_FLAG="--create-disk=name=$DISK_NAME,size=$DISK_SIZE,type=$DISK_TYPE,device-name=galaxy-data,auto-delete=no"

        # Extract numeric value from DISK_SIZE (remove 'GB' suffix)
        DISK_SIZE_GB="${DISK_SIZE%GB}"
    fi

    # Calculate disk persistence size in Gi (K8s will not accept size in GB)
    # Convert GB to GiB: GiB = GB * (1000^3 / 1024^3) ≈ GB * 0.931
    # Using integer arithmetic: GiB = (GB * 931) / 1000
    PV_SIZE=$(( (DISK_SIZE_GB * 931) / 1000 ))
    echo "ℹ NFS storage will be configured for ${PV_SIZE}Gi (converted from ${DISK_SIZE_GB}GB disk)"
else
    echo "ℹ Using ephemeral storage only (no persistent disk)."
fi

# Generate custom user_data.sh with values baked in
TEMP_USER_DATA=$(mktemp /tmp/user_data.XXXXXX.sh)
trap "rm -f $TEMP_USER_DATA" EXIT

cat > "$TEMP_USER_DATA" << 'EOF'
#cloud-config
runcmd:
  - |
    # Setup persistent disk if available
    DISK_DEVICE="/dev/disk/by-id/google-galaxy-data"
    if [ -b "$DISK_DEVICE" ]; then
      echo "[`date`] - Found persistent disk at $DISK_DEVICE"

      # Check if disk is already formatted
      if ! blkid "$DISK_DEVICE" > /dev/null 2>&1; then
        echo "[`date`] - Formatting disk $DISK_DEVICE with ext4"
        mkfs -t ext4 "$DISK_DEVICE"
      else
        echo "[`date`] - Disk $DISK_DEVICE is already formatted"
      fi

      # Create mount point and mount
      mkdir -p /mnt/block_storage
      mount "$DISK_DEVICE" /mnt/block_storage

      # Add to fstab for persistent mounting across reboots
      DISK_UUID=$(blkid -s UUID -o value "$DISK_DEVICE")
      if ! grep -q "$DISK_UUID" /etc/fstab; then
        echo "UUID=$DISK_UUID /mnt/block_storage ext4 defaults 0 2" >> /etc/fstab
      fi

      # Set proper ownership
      chown ubuntu:ubuntu /mnt/block_storage
      echo "[`date`] - Persistent disk mounted at /mnt/block_storage"
    else
      echo "[`date`] - No persistent disk found. Galaxy will use ephemeral storage."
    fi
  - |
    # Run ansible-pull as ubuntu user
    sudo -u ubuntu bash -c '
    export HOME=/home/ubuntu
    HOST_IP=$(curl -s ifconfig.me)

EOF

# Add the configuration values directly into the script
if [ "$EPHEMERAL_ONLY" = false ]; then
    PV_SIZE_VALUE="${PV_SIZE}Gi"
else
    PV_SIZE_VALUE="20Gi"
fi

# Convert values files list to JSON array
GALAXY_VALUES_FILES_JSON=$(echo "$GALAXY_VALUES_FILES_LIST" | sed -e 's/;/","/g' -e 's/^/["/' -e 's/$/"]/')

cat >> "$TEMP_USER_DATA" << EOF
    # Configuration from launch_vm.sh
    PV_SIZE="${PV_SIZE_VALUE}"
    GIT_REPO="${GIT_REPO}"
    GIT_BRANCH="${GIT_BRANCH}"
    GALAXY_CHART_VERSION="${GALAXY_CHART_VERSION}"
    GALAXY_DEPS_VERSION="${GALAXY_DEPS_VERSION}"
    GALAXY_VALUES_FILES_JSON='${GALAXY_VALUES_FILES_JSON}'
EOF

cat >> "$TEMP_USER_DATA" << 'EOF'

    mkdir -p /tmp/ansible-inventory
    cat > /tmp/ansible-inventory/localhost << INVEOF
    [vm]
    127.0.0.1 ansible_connection=local ansible_python_interpreter="/usr/bin/python3"

    [all:vars]
    ansible_user="ubuntu"
    rke2_token="defaultSecret12345"
    rke2_additional_sans=["${HOST_IP}"]
    rke2_debug=true
    nfs_size="${PV_SIZE}"
    galaxy_persistence_size="${PV_SIZE}"
    galaxy_db_password="gxy-db-password"
    galaxy_user="dev@galaxyproject.org"
    INVEOF

    echo "[`date`] - NFS storage size for Galaxy: ${PV_SIZE}"
    echo "[`date`] - Git Repository: ${GIT_REPO}"
    echo "[`date`] - Git Branch: ${GIT_BRANCH}"
    echo "[`date`] - Galaxy Chart Version: ${GALAXY_CHART_VERSION}"
    echo "[`date`] - Galaxy Deps Version: ${GALAXY_DEPS_VERSION}"
    echo "[`date`] - Galaxy Values Files: ${GALAXY_VALUES_FILES_JSON}"
    echo "[`date`] - Inventory file created at /tmp/ansible-inventory/localhost; running ansible-pull..."

    ANSIBLE_CALLBACKS_ENABLED=profile_tasks ANSIBLE_HOST_PATTERN_MISMATCH=ignore ansible-pull -U ${GIT_REPO} -C ${GIT_BRANCH} -d /home/ubuntu/ansible -i /tmp/ansible-inventory/localhost --accept-host-key --limit 127.0.0.1 --extra-vars "{\"galaxy_chart_version\": \"${GALAXY_CHART_VERSION}\", \"galaxy_deps_version\": \"${GALAXY_DEPS_VERSION}\", \"galaxy_values_files\": ${GALAXY_VALUES_FILES_JSON}}" playbook.yml

    echo "[`date`] - User data script completed."
    '

EOF

echo "ℹ Generated custom user_data.sh at $TEMP_USER_DATA"

# Launch the VM
echo "Launching VM '$INSTANCE_NAME'..."

# Build the gcloud command
GCLOUD_CMD=(
    gcloud compute instances create "$INSTANCE_NAME"
    --project="$PROJECT"
    --zone="$ZONE"
    --machine-type="$MACHINE_TYPE"
    --image="$MACHINE_IMAGE"
    --image-project="$PROJECT"
    --boot-disk-size="$BOOT_DISK_SIZE"
    --boot-disk-type="$DISK_TYPE"
    --tags=k8s,http-server,https-server
    --scopes=cloud-platform
    --metadata-from-file=user-data="$TEMP_USER_DATA"
    --metadata=ssh-keys="ubuntu:$SSH_KEY"
)

# Add disk flag if not ephemeral only
if [ "$EPHEMERAL_ONLY" = false ]; then
    GCLOUD_CMD+=($DISK_FLAG)
fi

# Execute the command
"${GCLOUD_CMD[@]}"

echo ""
echo "✓ Instance '$INSTANCE_NAME' created successfully."
echo ""

# Get the instance IP address
echo "Getting instance IP address..."
INSTANCE_IP=$(gcloud compute instances describe "$INSTANCE_NAME" --project="$PROJECT" --zone="$ZONE" --format='get(networkInterfaces[0].accessConfigs[0].natIP)')

if [ -n "$INSTANCE_IP" ]; then
    echo "Instance IP: $INSTANCE_IP"

    # Copy IP to clipboard on macOS
    if command -v pbcopy >/dev/null 2>&1; then
        echo "$INSTANCE_IP" | pbcopy
        echo "✓ IP address copied to clipboard"
    fi

    echo ""
    echo "The VM is now bootstrapping automatically. You can:"
    echo "1. Check cloud-init progress: gcloud compute ssh $INSTANCE_NAME --project=$PROJECT --zone=$ZONE --command='sudo tail -f /var/log/cloud-init-output.log'"
    echo "2. Monitor the deployment: gcloud compute ssh $INSTANCE_NAME --project=$PROJECT --zone=$ZONE --command='sudo journalctl -f -u cloud-final'"
    echo ""
    echo "Galaxy will be available at: http://$INSTANCE_IP/ once deployment completes."
else
    echo "Warning: Could not retrieve instance IP address"
    echo ""
    echo "The VM is now bootstrapping automatically. You can:"
    echo "1. Check cloud-init progress: gcloud compute ssh $INSTANCE_NAME --project=$PROJECT --zone=$ZONE --command='sudo tail -f /var/log/cloud-init-output.log'"
    echo "2. Monitor the deployment: gcloud compute ssh $INSTANCE_NAME --project=$PROJECT --zone=$ZONE --command='sudo journalctl -f -u cloud-final'"
    echo ""
    echo "Galaxy will be available at http://INSTANCE_IP/ once deployment completes."
fi
