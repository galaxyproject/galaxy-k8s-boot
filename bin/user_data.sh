#cloud-config
write_files:
  - path: /usr/local/bin/galaxy_bootstrap.sh
    permissions: '0755'
    owner: root:root
    content: |
      #!/bin/bash

      echo "[$(date)] - Starting galaxy_bootstrap script..."

      # 1. Setup persistent disk if available
      DISK_DEVICE="/dev/disk/by-id/google-galaxy-data"
      if [ -b "$DISK_DEVICE" ]; then
        echo "[$(date)] - Found persistent disk at $DISK_DEVICE"

        # Check if disk is already formatted
        if ! blkid "$DISK_DEVICE" > /dev/null 2>&1; then
          echo "[$(date)] - Formatting disk $DISK_DEVICE with ext4"
          mkfs -t ext4 "$DISK_DEVICE"
        else
          echo "[$(date)] - Disk $DISK_DEVICE is already formatted"
        fi

        # Create mount point and mount
        mkdir -p /mnt/block_storage
        mount "$DISK_DEVICE" /mnt/block_storage

        # Add to fstab for persistent mounting across reboots
        DISK_UUID=$(blkid -s UUID -o value "$DISK_DEVICE")
        if [ -n "$DISK_UUID" ] && ! grep -q "$DISK_UUID" /etc/fstab; then
          echo "UUID=$DISK_UUID /mnt/block_storage ext4 defaults 0 2" >> /etc/fstab
        fi

        # Set proper ownership
        chown debian:debian /mnt/block_storage
        echo "[$(date)] - Persistent disk mounted at /mnt/block_storage"
      else
        echo "[$(date)] - No persistent disk found at $DISK_DEVICE. Galaxy will use ephemeral storage."
      fi

      # 2. Setup PostgreSQL disk if available
      POSTGRES_DISK_DEVICE="/dev/disk/by-id/google-galaxy-postgres-data"
      if [ -b "$POSTGRES_DISK_DEVICE" ]; then
        echo "[$(date)] - Found PostgreSQL disk at $POSTGRES_DISK_DEVICE"

        # Check if disk is already formatted
        if ! blkid "$POSTGRES_DISK_DEVICE" > /dev/null 2>&1; then
          echo "[$(date)] - Formatting PostgreSQL disk $POSTGRES_DISK_DEVICE with ext4"
          mkfs -t ext4 "$POSTGRES_DISK_DEVICE"
        else
          echo "[$(date)] - PostgreSQL disk $POSTGRES_DISK_DEVICE is already formatted"
        fi

        # Create mount point and mount
        mkdir -p /mnt/postgres_storage
        mount "$POSTGRES_DISK_DEVICE" /mnt/postgres_storage

        # Add to fstab for persistent mounting across reboots
        POSTGRES_DISK_UUID=$(blkid -s UUID -o value "$POSTGRES_DISK_DEVICE")
        if [ -n "$POSTGRES_DISK_UUID" ] && ! grep -q "$POSTGRES_DISK_UUID" /etc/fstab; then
          echo "UUID=$POSTGRES_DISK_UUID /mnt/postgres_storage ext4 defaults 0 2" >> /etc/fstab
        fi

        # Set proper ownership
        chown debian:debian /mnt/postgres_storage
        echo "[$(date)] - PostgreSQL disk mounted at /mnt/postgres_storage"
      else
        echo "[$(date)] - No PostgreSQL disk found at $POSTGRES_DISK_DEVICE. PostgreSQL will use ephemeral storage."
      fi

      # 3. Run ansible-pull
      sudo -u debian bash -c '
      export HOME=/home/debian
      HOST_IP=$(curl -s ifconfig.me)

      PV_SIZE=$(curl -s -f "http://metadata.google.internal/computeMetadata/v1/instance/attributes/persistent-volume-size" -H "Metadata-Flavor: Google" 2>/dev/null)
      if [ -z "$PV_SIZE" ]; then
          echo "[$(date)] - persistent-volume-size metadata not found or empty, using default."
          PV_SIZE="139Gi"
      fi
      echo "[$(date)] - NFS storage size for Galaxy: ${PV_SIZE}"

      # Add restore_galaxy if enabled
      RESTORE_GALAXY=$(curl -s -f "http://metadata.google.internal/computeMetadata/v1/instance/attributes/restore_galaxy" -H "Metadata-Flavor: Google" 2>/dev/null || echo "false")

      # GCP project for the Batch runner. Empty -> the playbook auto-detects it from the
      # VM metadata (project/project-id). Set the gcp_project_id instance attribute
      # (from Leonardo/Terra) to target a different project.
      GCP_PROJECT_ID=$(curl -s -f "http://metadata.google.internal/computeMetadata/v1/instance/attributes/gcp_project_id" -H "Metadata-Flavor: Google" 2>/dev/null || echo "")
      echo "[$(date)] - GCP project id (empty = auto-detect): ${GCP_PROJECT_ID}"

      # Empty -> the playbook derives galaxy-batch-runner@<gcp_project_id>... so the
      # service account follows the project instead of being pinned to one.
      GCP_BATCH_SERVICE_ACCOUNT_EMAIL=$(curl -s -f "http://metadata.google.internal/computeMetadata/v1/instance/attributes/gcp_batch_service_account_email" -H "Metadata-Flavor: Google" 2>/dev/null || echo "")
      echo "[$(date)] - GCP Batch service account email (empty = derive from project): ${GCP_BATCH_SERVICE_ACCOUNT_EMAIL}"

      # Optional override of the Batch VM image name; empty -> the role default.
      GCP_BATCH_VM_IMAGE=$(curl -s -f "http://metadata.google.internal/computeMetadata/v1/instance/attributes/gcp_batch_vm_image" -H "Metadata-Flavor: Google" 2>/dev/null || echo "")

      # VPC network / subnet the Batch VMs join. Leonardo injects these so Batch VMs
      # land in the same project VPC as the Galaxy VM and can reach NFS. Empty -> the
      # value in the Helm values files is used unchanged.
      GCP_BATCH_NETWORK=$(curl -s -f "http://metadata.google.internal/computeMetadata/v1/instance/attributes/gcp-network" -H "Metadata-Flavor: Google" 2>/dev/null || echo "")
      GCP_BATCH_SUBNET=$(curl -s -f "http://metadata.google.internal/computeMetadata/v1/instance/attributes/gcp-subnet" -H "Metadata-Flavor: Google" 2>/dev/null || echo "")
      echo "[$(date)] - GCP Batch network/subnet (empty = values default): ${GCP_BATCH_NETWORK}/${GCP_BATCH_SUBNET}"

      # Set this to "true" only when an external L7 proxy terminates TLS and is the
      # only way in (e.g. Leonardo on Terra). It makes ingress-nginx trust the
      # caller-supplied X-Forwarded-* headers, which is what lets tusd generate
      # https:// upload URLs instead of http:// ones the browser blocks as mixed
      # content. On a directly reachable VM it would let anyone forge those headers.
      INGRESS_USE_FORWARDED_HEADERS=$(curl -s -f "http://metadata.google.internal/computeMetadata/v1/instance/attributes/ingress_use_forwarded_headers" -H "Metadata-Flavor: Google" 2>/dev/null || echo "false")
      echo "[$(date)] - Trust caller-supplied X-Forwarded-* headers: ${INGRESS_USE_FORWARDED_HEADERS}"

      # Terra / AnVIL launch context — baked in at VM launch time by the
      # orchestrating service (e.g. Leonardo). These are intentionally literal
      # values, not metadata reads, so the orchestrator substitutes them before
      # the script is sent to the instance.
      TERRA_WORKSPACE=""
      TERRA_NAMESPACE=""
      TERRA_DRS_URL=""
      TERRA_API_URL=""

      GIT_REPO=$(curl -s -f "http://metadata.google.internal/computeMetadata/v1/instance/attributes/git-repo" -H "Metadata-Flavor: Google" 2>/dev/null || echo "https://github.com/galaxyproject/galaxy-k8s-boot.git")
      GIT_BRANCH=$(curl -s -f "http://metadata.google.internal/computeMetadata/v1/instance/attributes/git-branch" -H "Metadata-Flavor: Google" 2>/dev/null || echo "master")

      PULL_ARGS=(
        -U "${GIT_REPO}"
        -C "${GIT_BRANCH}"
        -d /home/debian/ansible
        -i /tmp/ansible-inventory/localhost
        --accept-host-key
        --limit 127.0.0.1
        --extra-vars "gcp_project_id=${GCP_PROJECT_ID}"
        --extra-vars "gcp_batch_service_account_email=${GCP_BATCH_SERVICE_ACCOUNT_EMAIL}"
        --extra-vars "gcp_batch_network=${GCP_BATCH_NETWORK}"
        --extra-vars "gcp_batch_subnet=${GCP_BATCH_SUBNET}"
        --extra-vars "terra_workspace=${TERRA_WORKSPACE}"
        --extra-vars "terra_namespace=${TERRA_NAMESPACE}"
        --extra-vars "terra_drs_url=${TERRA_DRS_URL}"
        --extra-vars "terra_api_url=${TERRA_API_URL}"
        --extra-vars "ingress_use_forwarded_headers=${INGRESS_USE_FORWARDED_HEADERS}"
      )

      # Only override the Batch VM image when set; empty leaves the role default.
      if [ -n "${GCP_BATCH_VM_IMAGE}" ]; then
          PULL_ARGS+=(--extra-vars "gcp_batch_vm_image=${GCP_BATCH_VM_IMAGE}")
      fi

      if [ "$RESTORE_GALAXY" = "true" ]; then
          PULL_ARGS+=(--extra-vars "restore_galaxy=true")
          echo "[$(date)] - Galaxy Restore Mode: Enabled"
      else
          echo "[$(date)] - Galaxy Restore Mode: Disabled"
      fi

      PULL_ARGS+=(playbook.yml)

      mkdir -p /tmp/ansible-inventory
      cat > /tmp/ansible-inventory/localhost << EOF
      [vms]
      127.0.0.1 ansible_connection=local ansible_python_interpreter="/usr/bin/python3"

      [all:vars]
      ansible_user="debian"
      rke2_token="defaultSecret12345"
      rke2_additional_sans=["${HOST_IP}"]
      rke2_debug=true
      nfs_size="${PV_SIZE}"
      galaxy_persistence_size="${PV_SIZE}"
      galaxy_db_password="gxy-db-password"
      galaxy_user="dev@galaxyproject.org"
      EOF

      echo "[$(date)] - Inventory file created at /tmp/ansible-inventory/localhost; running ansible-pull..."
      echo "[$(date)] - Running: ANSIBLE_CALLBACKS_ENABLED=profile_tasks ANSIBLE_HOST_PATTERN_MISMATCH=ignore ansible-pull ${PULL_ARGS[@]}"

      ANSIBLE_CALLBACKS_ENABLED=profile_tasks ANSIBLE_HOST_PATTERN_MISMATCH=ignore ansible-pull "${PULL_ARGS[@]}"
      '

      echo "[$(date)] - Bootstrap script completed."

runcmd:
  - /usr/local/bin/galaxy_bootstrap.sh
