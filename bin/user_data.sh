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

    # Get configuration from metadata with fallback defaults
    PV_SIZE=$(curl -s -f "http://metadata.google.internal/computeMetadata/v1/instance/attributes/persistent-volume-size" -H "Metadata-Flavor: Google" 2>/dev/null || echo "20Gi")
    GALAXY_CHART_VERSION=$(curl -s -f "http://metadata.google.internal/computeMetadata/v1/instance/attributes/galaxy-chart-version" -H "Metadata-Flavor: Google" 2>/dev/null || echo "6.6.0")
    GALAXY_DEPS_VERSION=$(curl -s -f "http://metadata.google.internal/computeMetadata/v1/instance/attributes/galaxy-deps-version" -H "Metadata-Flavor: Google" 2>/dev/null || echo "1.1.1")
    GALAXY_VALUES_FILES_LIST=$(curl -s -f "http://metadata.google.internal/computeMetadata/v1/instance/attributes/galaxy-values-files" -H "Metadata-Flavor: Google" 2>/dev/null || echo "values/values.yml")

    # Convert semicolon-separated values files to JSON array for Ansible
    GALAXY_VALUES_FILES_JSON=$(echo "$GALAXY_VALUES_FILES_LIST" | sed -e 's/;/","/g' -e 's/^/["/' -e 's/$/"]/')

    mkdir -p /tmp/ansible-inventory
    cat > /tmp/ansible-inventory/localhost << EOF
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
    EOF

    echo "[`date`] - NFS storage size for Galaxy: ${PV_SIZE}"
    echo "[`date`] - Galaxy Chart Version: ${GALAXY_CHART_VERSION}"
    echo "[`date`] - Galaxy Deps Version: ${GALAXY_DEPS_VERSION}"
    echo "[`date`] - Galaxy Values Files: ${GALAXY_VALUES_FILES_LIST}"
    echo "[`date`] - Inventory file created at /tmp/ansible-inventory/localhost; running ansible-pull..."

    ANSIBLE_CALLBACKS_ENABLED=profile_tasks ANSIBLE_HOST_PATTERN_MISMATCH=ignore ansible-pull -U https://github.com/galaxyproject/galaxy-k8s-boot.git -C master -d /home/ubuntu/ansible -i /tmp/ansible-inventory/localhost --accept-host-key --limit 127.0.0.1 --extra-vars "galaxy_chart_version=${GALAXY_CHART_VERSION}" --extra-vars "galaxy_deps_version=${GALAXY_DEPS_VERSION}" --extra-vars "galaxy_values_files=${GALAXY_VALUES_FILES_JSON}" playbook.yml

    echo "[`date`] - User data script completed."
    '
