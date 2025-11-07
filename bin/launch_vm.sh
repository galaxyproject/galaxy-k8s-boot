#!/bin/bash

# Galaxy Kubernetes Boot VM Launch Script
# This script handles VM creation with automatic persistent disk management

set -e

# Default values
PROJECT="anvil-and-terra-development"
ZONE="us-east4-c"
MACHINE_TYPE="e2-standard-4"
MACHINE_IMAGE="galaxy-k8s-boot-v2025-11-04"
BOOT_DISK_SIZE="100GB"
DISK_SIZE="150GB"
DISK_TYPE="pd-balanced"

# Parse command line arguments
INSTANCE_NAME=""
DISK_NAME=""
SSH_KEY=""
EPHEMERAL_ONLY=false

usage() {
    cat << EOF
Usage: $0 [OPTIONS] INSTANCE_NAME

Launch a Galaxy Kubernetes VM with automatic persistent disk management.

Required Arguments:
  INSTANCE_NAME       Name of the VM instance to create

Options:
  -p, --project PROJECT        GCP project ID (default: $PROJECT)
  -z, --zone ZONE             GCP zone (default: $ZONE)
  -i, --machine-image IMAGE   Machine image name (default: $MACHINE_IMAGE)
  -d, --disk-name DISK_NAME   Name of persistent disk (default: galaxy-data-INSTANCE_NAME)
  -s, --disk-size SIZE        Size of persistent disk (default: $DISK_SIZE)
  -k, --ssh-key SSH_KEY       SSH public key for ubuntu user (required)
  -m, --machine-type TYPE     Machine type (default: $MACHINE_TYPE)
  --ephemeral-only            Create VM without persistent disk
  -h, --help                  Show this help message

Examples:
  # Launch VM with new or existing disk
  $0 -k "ssh-rsa AAAAB3..." my-galaxy-vm

  # Launch VM with specific machine image
  $0 -k "ssh-rsa AAAAB3..." -i galaxy-k8s-boot-v2025-11-04 my-galaxy-vm

  # Launch VM with specific disk name
  $0 -k "ssh-rsa AAAAB3..." -d galaxy-shared-disk my-galaxy-vm

  # Create VM without persistent storage (testing only)
  $0 -k "ssh-rsa AAAAB3..." --ephemeral-only my-galaxy-vm

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

echo "=== Galaxy Kubernetes Boot VM Launch ==="
echo "Instance Name: $INSTANCE_NAME"
echo "Project: $PROJECT"
echo "Zone: $ZONE"
echo "Machine Type: $MACHINE_TYPE"
echo "Machine Image: $MACHINE_IMAGE"

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
else
    echo "ℹ Using ephemeral storage only (no persistent disk)."
fi

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
    --metadata-from-file=user-data=bin/user_data.sh
)

# Build metadata string
METADATA="ssh-keys=ubuntu:$SSH_KEY"
if [ "$EPHEMERAL_ONLY" = false ]; then
    METADATA="${METADATA},persistent-disk-size=${DISK_SIZE_GB}GB"
fi

# Add combined metadata
GCLOUD_CMD+=(--metadata="$METADATA")

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
