#!/usr/bin/env bash

# Galaxy K8s Boot - End-to-End Image Builder
# Creates a GCE VM, runs the image preparation playbook, snapshots the image,
# and cleans up. One command, start to finish.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Defaults
PROJECT="anvil-and-terra-development"
ZONE="us-east4-c"
MACHINE_TYPE="n1-standard-2"
BOOT_DISK_SIZE="100GB"
OS="debian12"
VM_NAME="galaxy-image-prep"
IMAGE_FAMILY="galaxy-k8s-boot"
IMAGE_NAME=""
PLAYBOOK="image_prep.yml"
KEEP_VM=false
DRY_RUN=false
VERBOSE=""

# Temp files to clean up
INVENTORY_FILE=""

cleanup() {
    [[ -n "$INVENTORY_FILE" && -f "$INVENTORY_FILE" ]] && rm -f "$INVENTORY_FILE"
    return 0
}
trap cleanup EXIT

# OS presets: image-family, image-project, ssh-user
resolve_os_preset() {
    local os="$1" field="$2"
    case "$os:$field" in
        debian12:family)  echo "debian-12" ;;
        debian12:project) echo "debian-cloud" ;;
        debian12:user)    echo "debian" ;;
        ubuntu2404:family)  echo "ubuntu-2404-lts-amd64" ;;
        ubuntu2404:project) echo "ubuntu-os-cloud" ;;
        ubuntu2404:user)    echo "ubuntu" ;;
        *) return 1 ;;
    esac
}

# ANSI formatting
reset="\033[0m"
bold="\033[1m"

hi() { echo -e "$bold$@$reset"; }

NAME=$(basename "$0")

help() {
    cat << EOF

$(hi NAME)
    $NAME

$(hi DESCRIPTION)
    End-to-end GCE image builder for Galaxy K8s Boot. Creates a temporary VM,
    runs the Ansible image preparation playbook, snapshots the result as a GCE
    image, and deletes the VM.

$(hi SYNOPSIS)
    $NAME [OPTIONS]

$(hi OPTIONS)
    $(hi --os) OS              Base OS preset: $(hi debian12) or $(hi ubuntu2404). Default $(hi $OS)
    $(hi --name) NAME          Override the output image name
    $(hi --zone) ZONE          GCP zone. Default $(hi $ZONE)
    $(hi --project) PROJECT    GCP project. Default $(hi $PROJECT)
    $(hi --machine-type) TYPE  VM machine type. Default $(hi $MACHINE_TYPE)
    $(hi --vm-name) NAME       Override temporary VM name. Default $(hi $VM_NAME)
    $(hi --keep-vm)            Don't delete VM after image creation (for debugging)
    $(hi -v)|$(hi --verbose)          Verbose Ansible output
    $(hi -n)|$(hi --dry-run)          Show what would be done without executing
    $(hi -h)|$(hi --help)             Show this help message

$(hi OS PRESETS)
    $(hi debian12)     Debian 12 (debian-cloud/debian-12), user=$(hi debian)
    $(hi ubuntu2404)   Ubuntu 24.04 LTS (ubuntu-os-cloud/ubuntu-2404-lts-amd64), user=$(hi ubuntu)

$(hi IMAGE NAMING)
    By default the image is named:
        galaxy-k8s-boot-v{YYYY-MM-DD}
    For example: $(hi galaxy-k8s-boot-v2026-02-24)
    Override with $(hi --name).

$(hi EXAMPLES)
    \$> $NAME
    \$> $NAME --dry-run
    \$> $NAME --os ubuntu2404
    \$> $NAME --name galaxy-k8s-boot-custom-v1
    \$> $NAME --keep-vm --verbose

EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --os) OS="$2"; shift 2 ;;
        --name) IMAGE_NAME="$2"; shift 2 ;;
        --zone) ZONE="$2"; shift 2 ;;
        --project) PROJECT="$2"; shift 2 ;;
        --machine-type) MACHINE_TYPE="$2"; shift 2 ;;
        --vm-name) VM_NAME="$2"; shift 2 ;;
        --keep-vm) KEEP_VM=true; shift ;;
        -v|--verbose) VERBOSE="-v"; shift ;;
        -n|--dry-run) DRY_RUN=true; shift ;;
        -h|--help|help) help; exit 0 ;;
        *)
            echo "Unknown option: $1"
            help
            exit 1
            ;;
    esac
done

# Validate OS preset
if ! resolve_os_preset "$OS" family > /dev/null 2>&1; then
    echo "Error: Unknown OS preset '$OS'. Choose debian12 or ubuntu2404."
    exit 1
fi

BASE_FAMILY=$(resolve_os_preset "$OS" family)
BASE_PROJECT=$(resolve_os_preset "$OS" project)
SSH_USER=$(resolve_os_preset "$OS" user)

# Generate image name if not overridden
if [[ -z "$IMAGE_NAME" ]]; then
    IMAGE_NAME="galaxy-k8s-boot-v$(date +%Y-%m-%d)"
fi

# Resolve the latest base image from the family
BASE_IMAGE=$(gcloud compute images describe-from-family "$BASE_FAMILY" \
    --project="$BASE_PROJECT" --format='get(name)' 2>/dev/null || true)

if [[ -z "$BASE_IMAGE" ]]; then
    echo "Error: Could not resolve base image from family '$BASE_FAMILY' in project '$BASE_PROJECT'"
    exit 1
fi

# --- Dry-run summary ---
if [[ "$DRY_RUN" == "true" ]]; then
    echo ""
    echo "==> Dry run — the following steps would be performed:"
    echo ""
    echo "  1. Create VM:"
    echo "     gcloud compute instances create $VM_NAME \\"
    echo "         --project=$PROJECT \\"
    echo "         --zone=$ZONE \\"
    echo "         --machine-type=$MACHINE_TYPE \\"
    echo "         --image=$BASE_IMAGE \\"
    echo "         --image-project=$BASE_PROJECT \\"
    echo "         --boot-disk-size=$BOOT_DISK_SIZE \\"
    echo "         --boot-disk-type=pd-balanced \\"
    echo "         --scopes=cloud-platform \\"
    echo "         --metadata=enable-oslogin=FALSE,ssh-keys=\"$SSH_USER:<gcloud-public-key>\""
    echo ""
    echo "  2. Wait for SSH readiness"
    echo ""
    echo "  3. Run Ansible playbook:"
    echo "     ansible-playbook -i <inventory> $PROJECT_ROOT/$PLAYBOOK${VERBOSE:+ $VERBOSE}"
    echo "     (inventory: $SSH_USER@<external-ip>, key: ~/.ssh/google_compute_engine)"
    echo ""
    echo "  4. Stop VM:"
    echo "     gcloud compute instances stop $VM_NAME \\"
    echo "         --project=$PROJECT \\"
    echo "         --zone=$ZONE"
    echo ""
    echo "  5. Create GCE image:"
    echo "     gcloud compute images create $IMAGE_NAME \\"
    echo "         --project=$PROJECT \\"
    echo "         --source-disk=$VM_NAME \\"
    echo "         --source-disk-zone=$ZONE \\"
    echo "         --family=$IMAGE_FAMILY \\"
    echo "         --storage-location=us"
    echo ""
    if [[ "$KEEP_VM" == "true" ]]; then
        echo "  6. Keep VM (--keep-vm set)"
    else
        echo "  6. Delete VM:"
        echo "     gcloud compute instances delete $VM_NAME \\"
        echo "         --project=$PROJECT \\"
        echo "         --zone=$ZONE"
    fi
    echo ""
    exit 0
fi

# --- Step 1: Create VM ---
# Ensure gcloud SSH key exists (gcloud creates this pair automatically on first use)
GCLOUD_SSH_KEY="$HOME/.ssh/google_compute_engine"
if [[ ! -f "$GCLOUD_SSH_KEY" ]]; then
    echo "Error: $GCLOUD_SSH_KEY not found."
    echo "Run 'gcloud compute ssh' to any VM once to generate it, then retry."
    exit 1
fi
GCLOUD_SSH_PUB=$(cat "${GCLOUD_SSH_KEY}.pub")

echo "==> Creating VM '$VM_NAME' ($BASE_FAMILY, $MACHINE_TYPE)..."
gcloud compute instances create "$VM_NAME" \
    --project="$PROJECT" \
    --zone="$ZONE" \
    --machine-type="$MACHINE_TYPE" \
    --image="$BASE_IMAGE" \
    --image-project="$BASE_PROJECT" \
    --boot-disk-size="$BOOT_DISK_SIZE" \
    --boot-disk-type=pd-balanced \
    --scopes=cloud-platform \
    --metadata=enable-oslogin=FALSE,ssh-keys="$SSH_USER:$GCLOUD_SSH_PUB"

# From here on, if anything fails, tell the user the VM name so they can clean up
fail() {
    echo ""
    echo "!!! Step failed. The VM '$VM_NAME' still exists in project '$PROJECT', zone '$ZONE'."
    echo "!!! To clean up manually:"
    echo "!!!   gcloud compute instances delete $VM_NAME --project=$PROJECT --zone=$ZONE --quiet"
    exit 1
}
trap 'cleanup; fail' ERR

# --- Step 2: Wait for SSH ---
echo "==> Waiting for SSH..."
for i in $(seq 1 30); do
    if gcloud compute ssh "$SSH_USER@$VM_NAME" \
        --project="$PROJECT" \
        --zone="$ZONE" \
        --ssh-key-file="$GCLOUD_SSH_KEY" \
        --command="true" \
        --ssh-flag="-o StrictHostKeyChecking=no" \
        --ssh-flag="-o UserKnownHostsFile=/dev/null" \
        --quiet 2>/dev/null; then
        break
    fi
    if [[ $i -eq 30 ]]; then
        echo "Error: SSH not ready after 30 attempts"
        exit 1
    fi
    sleep 5
done

# --- Step 3: Get external IP and run playbook ---
EXTERNAL_IP=$(gcloud compute instances describe "$VM_NAME" \
    --project="$PROJECT" \
    --zone="$ZONE" \
    --format='get(networkInterfaces[0].accessConfigs[0].natIP)')

if [[ -z "$EXTERNAL_IP" ]]; then
    echo "Error: Could not get external IP for '$VM_NAME'"
    exit 1
fi

# Generate temporary inventory
INVENTORY_FILE=$(mktemp /tmp/galaxy-image-prep-inventory.XXXXXX)
cat > "$INVENTORY_FILE" << EOF
[image_targets]
$EXTERNAL_IP

[image_targets:vars]
ansible_user=$SSH_USER
ansible_ssh_private_key_file=~/.ssh/google_compute_engine
ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
ansible_python_interpreter=/usr/bin/python3
EOF

echo "==> Running image preparation playbook..."
ansible-playbook \
    -i "$INVENTORY_FILE" \
    "$PROJECT_ROOT/$PLAYBOOK" \
    $VERBOSE

# --- Step 4: Stop VM ---
echo "==> Stopping VM..."
gcloud compute instances stop "$VM_NAME" \
    --project="$PROJECT" \
    --zone="$ZONE" \
    --quiet

# --- Step 5: Create image ---
echo "==> Creating image '$IMAGE_NAME'..."
gcloud compute images create "$IMAGE_NAME" \
    --project="$PROJECT" \
    --source-disk="$VM_NAME" \
    --source-disk-zone="$ZONE" \
    --family="$IMAGE_FAMILY" \
    --storage-location=us

# --- Step 6: Delete VM (unless --keep-vm) ---
# Restore normal trap (success path)
trap cleanup EXIT

if [[ "$KEEP_VM" == "true" ]]; then
    echo "==> Keeping VM '$VM_NAME' (--keep-vm)"
else
    echo "==> Deleting VM..."
    gcloud compute instances delete "$VM_NAME" \
        --project="$PROJECT" \
        --zone="$ZONE" \
        --quiet
fi

echo "==> Done! Image: $IMAGE_NAME"
