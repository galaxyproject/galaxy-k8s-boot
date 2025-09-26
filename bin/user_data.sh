#cloud-config
runcmd:
  - |
    # Run ansible-pull as ubuntu user
    sudo -u ubuntu bash -c '
    export HOME=/home/ubuntu
    HOST_IP=$(curl -s ifconfig.me)
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
    EOF

    ANSIBLE_CALLBACKS_ENABLED=profile_tasks ansible-pull -U https://github.com/galaxyproject/galaxy-k8s-boot.git -C master -d /home/ubuntu/ansible -i /tmp/ansible-inventory/localhost --accept-host-key deploy-galaxy.yml
    '
