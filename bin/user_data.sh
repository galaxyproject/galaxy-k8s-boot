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

    # Get Galaxy persistence size from metadata if available
    GXY_PERSISTENCE_SIZE=$(curl -s -f "http://metadata.google.internal/computeMetadata/v1/instance/attributes/gxy-persistence-size" -H "Metadata-Flavor: Google" 2>/dev/null || echo "20Gi")

    mkdir -p /tmp/ansible-inventory
    cat > /tmp/ansible-inventory/localhost << EOF
    [k8s_cluster]
    127.0.0.1 ansible_connection=local ansible_python_interpreter="/usr/bin/python3"

    [all:vars]
    ansible_user="ubuntu"
    rke2_token="defaultSecret12345"
    rke2_additional_sans=["${HOST_IP}"]
    rke2_bind_address="0.0.0.0"
    rke2_disable=["rke2-traefik", "rke2-ingress-nginx"]
    rke2_debug=true
    gxy_persistence_size="${GXY_PERSISTENCE_SIZE}"
    gxy_db_password="gxy-db-password"
    gxy_user="dev@galaxyproject.org"
    EOF

    echo "[`date`] - Inventory file created at /tmp/ansible-inventory/localhost; running ansible-pull..."
    echo "[`date`] - Galaxy persistence size: ${GXY_PERSISTENCE_SIZE}"

    ANSIBLE_CALLBACKS_ENABLED=profile_tasks ANSIBLE_HOST_PATTERN_MISMATCH=ignore ansible-pull -U https://github.com/galaxyproject/galaxy-k8s-boot.git -C master -d /home/ubuntu/ansible -i /tmp/ansible-inventory/localhost --accept-host-key --limit 127.0.0.1 deploy-galaxy.yml

    echo "[`date`] - User data script completed."
    '
