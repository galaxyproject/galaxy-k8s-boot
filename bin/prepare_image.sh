#!/bin/bash

# Galaxy K8s Boot - Image Preparation Script
# This script helps prepare machine images with pre-installed components

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INVENTORY_FILE=""
PLAYBOOK="image_prep.yml"
EXTRA_VARS=""
DRY_RUN=false
VERBOSE=""

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Prepare a machine image with Galaxy K8s Boot components pre-installed.

OPTIONS:
    -i, --inventory FILE    Inventory file (required)
    -e, --extra-vars VARS   Extra variables in key=value format
    -n, --dry-run          Run in check mode (don't make changes)
    -v, --verbose          Verbose output
    -h, --help             Show this help message

EXAMPLES:
    # Basic usage for GCP
    $0 -i inventories/my_image_prep

    # With custom K3s version
    $0 -i inventories/my_image_prep -e "k3s_version=v1.29.0+k3s1"

    # Dry run to see what would be done
    $0 -i inventories/my_image_prep --dry-run

    # Skip CVMFS installation
    $0 -i inventories/my_image_prep -e "install_cvmfs=false"

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -i|--inventory)
            INVENTORY_FILE="$2"
            shift 2
            ;;
        -e|--extra-vars)
            if [[ -n "$EXTRA_VARS" ]]; then
                EXTRA_VARS="$EXTRA_VARS $2"
            else
                EXTRA_VARS="$2"
            fi
            shift 2
            ;;
        -n|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -v|--verbose)
            VERBOSE="-v"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Validate required parameters
if [[ -z "$INVENTORY_FILE" ]]; then
    echo "Error - Inventory file is required (-i/--inventory)"
    echo
    usage
    exit 1
fi

if [[ ! -f "$INVENTORY_FILE" ]]; then
    echo "Error: Inventory file not found: $INVENTORY_FILE"
    echo
    echo "Available inventory examples:"
    echo "  inventories/image_prep.example"
    echo "  inventories/image_prep"
    echo
    echo "You can create one by copying the example:"
    echo "  cp inventories/image_prep.example $INVENTORY_FILE"
    echo "  # Edit $INVENTORY_FILE with your instance details"
    exit 1
fi

# Check if playbook exists
if [[ ! -f "$PROJECT_ROOT/$PLAYBOOK" ]]; then
    echo "Error: Playbook not found: $PROJECT_ROOT/$PLAYBOOK"
    exit 1
fi

# Build ansible-playbook command
CMD="ansible-playbook"
CMD="$CMD -i $INVENTORY_FILE"
CMD="$CMD $PROJECT_ROOT/$PLAYBOOK"

if [[ "$DRY_RUN" == "true" ]]; then
    CMD="$CMD --check"
    echo "=== DRY RUN MODE - No changes will be made ==="
fi

if [[ -n "$VERBOSE" ]]; then
    CMD="$CMD $VERBOSE"
fi

if [[ -n "$EXTRA_VARS" ]]; then
    CMD="$CMD -e '$EXTRA_VARS'"
fi

echo "=== Galaxy K8s Boot Image Preparation ==="
echo "Inventory: $INVENTORY_FILE"
echo "Playbook: $PLAYBOOK"
if [[ -n "$EXTRA_VARS" ]]; then
    echo "Extra vars: $EXTRA_VARS"
fi
echo "Command: $CMD"
echo

# Change to project root directory and run
cd "$PROJECT_ROOT"

# Install role dependencies first
echo "=== Installing Ansible role dependencies ==="
if [[ -f "requirements.yml" ]]; then
    ansible-galaxy install -r requirements.yml
    if [[ $? -ne 0 ]]; then
        echo "Failed to install role dependencies"
        exit 1
    fi
    echo
fi

echo "=== Starting image preparation ==="
eval $CMD

if [[ $? -eq 0 ]]; then
    echo
    echo "=== Image preparation completed successfully! ==="
    if [[ "$DRY_RUN" != "true" ]]; then
        echo
        echo "Next steps:"
        echo "1. Create an image from the prepared instance"
        echo "2. Use the prepared image for faster K8s deployments with:"
        echo "   ansible-playbook -i your_cluster_inventory deploy.yml"
        echo
    fi
else
    echo
    echo "=== Image preparation failed! ==="
    echo "Check the output above for errors."
    exit 1
fi
