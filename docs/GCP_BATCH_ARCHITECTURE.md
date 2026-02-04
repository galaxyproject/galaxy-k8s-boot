# GCP Batch Integration Architecture

This document describes the architecture of GCP Batch integration in Galaxy Kubernetes Boot, including both the direct GCP Batch runner and the Pulsar-based GCP Batch runner.

## Overview

Galaxy Kubernetes Boot supports two different approaches for running Galaxy jobs on Google Cloud Platform Batch:

| Runner | Class | File Access | Communication |
|--------|-------|-------------|---------------|
| **Direct GCP Batch** | `GoogleCloudBatchJobRunner` | NFS mount | GCP Batch API |
| **Pulsar GCP Batch** | `PulsarGcpBatchJobRunner` | Local SSD | RabbitMQ |

Both runners allow Galaxy to offload compute-intensive jobs to GCP Batch VMs, which provides:
- Dynamic scaling based on workload
- Access to various machine types (including GPUs)
- Cost optimization through preemptible instances
- Isolation from the Kubernetes cluster

## Architecture Diagrams

### Direct GCP Batch Runner (NFS-based)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           RKE2 Kubernetes Cluster                            │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                         Galaxy Namespace                              │   │
│  │  ┌─────────────────┐   ┌─────────────────┐   ┌─────────────────┐     │   │
│  │  │  Galaxy Web     │   │  Galaxy Job     │   │   RabbitMQ      │     │   │
│  │  │  Deployment     │   │  Handler        │   │   (internal)    │     │   │
│  │  └─────────────────┘   └────────┬────────┘   └─────────────────┘     │   │
│  │                                 │                                     │   │
│  │                         GCP Batch API                                 │   │
│  │                                 │                                     │   │
│  └─────────────────────────────────┼─────────────────────────────────────┘   │
│                                    │                                         │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                      NFS Provisioner Namespace                        │   │
│  │  ┌─────────────────────────────────────────────────────────────┐     │   │
│  │  │                   NFS Server Pod                             │     │   │
│  │  │                   (Persistent Disk)                          │     │   │
│  │  └──────────────────────────────┬──────────────────────────────┘     │   │
│  │                                 │                                     │   │
│  │                     External IP: 10.150.0.X                          │   │
│  │                                 │                                     │   │
│  └─────────────────────────────────┼─────────────────────────────────────┘   │
│                                    │                                         │
└────────────────────────────────────┼─────────────────────────────────────────┘
                                     │
                        ┌────────────┴────────────┐
                        │   GCP VPC Network       │
                        │   (Firewall: port 2049) │
                        └────────────┬────────────┘
                                     │
┌────────────────────────────────────┼─────────────────────────────────────────┐
│                          GCP Batch VM                                         │
│  ┌─────────────────────────────────────────────────────────────────────────┐ │
│  │                        Tool Container                                    │ │
│  │  ┌───────────────────────────────────────────────────────────────────┐  │ │
│  │  │  /galaxy/server/database  ◄───────────────────────────────── NFS  │  │ │
│  │  │  (mounted from NFS server)                                        │  │ │
│  │  │                                                                   │  │ │
│  │  │  - Direct file access to Galaxy working directory                 │  │ │
│  │  │  - Input files read directly from NFS                             │  │ │
│  │  │  - Output files written directly to NFS                           │  │ │
│  │  └───────────────────────────────────────────────────────────────────┘  │ │
│  └─────────────────────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Pulsar GCP Batch Runner (SSD-based)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           RKE2 Kubernetes Cluster                            │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                         Galaxy Namespace                              │   │
│  │  ┌─────────────────┐   ┌─────────────────┐   ┌─────────────────┐     │   │
│  │  │  Galaxy Web     │   │  Galaxy Job     │   │   RabbitMQ      │     │   │
│  │  │  Deployment     │   │  Handler        │   │   Server        │     │   │
│  │  └─────────────────┘   └────────┬────────┘   └────────┬────────┘     │   │
│  │                                 │                      │              │   │
│  │                          AMQP Messages          External IP          │   │
│  │                                 │               10.150.0.X:5672       │   │
│  │                                 │                      │              │   │
│  └─────────────────────────────────┼──────────────────────┼──────────────┘   │
│                                    │                      │                  │
└────────────────────────────────────┼──────────────────────┼──────────────────┘
                                     │                      │
                        ┌────────────┴──────────────────────┴─────┐
                        │        GCP VPC Network                   │
                        │   (Firewall: port 5672 for RabbitMQ)    │
                        └────────────┬────────────────────────────┘
                                     │
┌────────────────────────────────────┼─────────────────────────────────────────┐
│                          GCP Batch VM                                         │
│  ┌─────────────────────────────────────────────────────────────────────────┐ │
│  │  Pulsar Sidecar Container              Tool Container                   │ │
│  │  ┌─────────────────────────┐          ┌───────────────────────────────┐ │ │
│  │  │ galaxy/pulsar-pod-      │          │                               │ │ │
│  │  │ staging:0.15.0.2        │          │  Tool Execution               │ │ │
│  │  │                         │◄────────►│                               │ │ │
│  │  │ - Connects to RabbitMQ  │  Shared  │  - Reads inputs from SSD      │ │ │
│  │  │ - Downloads inputs      │  Volume  │  - Writes outputs to SSD      │ │ │
│  │  │ - Uploads outputs       │          │  - Fast local I/O             │ │ │
│  │  │ - Handles job lifecycle │          │                               │ │ │
│  │  └───────────┬─────────────┘          └───────────────┬───────────────┘ │ │
│  │              │                                        │                  │ │
│  │              └──────────────┬─────────────────────────┘                  │ │
│  │                             │                                            │ │
│  │              ┌──────────────┴──────────────┐                             │ │
│  │              │      Local SSD              │                             │ │
│  │              │  /mnt/disks/pulsar_staging  │                             │ │
│  │              │  (375 GB increments)        │                             │ │
│  │              └─────────────────────────────┘                             │ │
│  └─────────────────────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────────────────┘
```

## Data Flow Comparison

### Direct GCP Batch Data Flow

```
1. Job Submission
   Galaxy ──► GCP Batch API ──► Create VM with NFS mount

2. Job Execution
   Tool reads input ◄── NFS ──► Galaxy working directory
   Tool writes output ──► NFS ──► Galaxy working directory

3. Job Completion
   Galaxy polls GCP Batch API ──► Job complete
   Output files already on NFS ──► Immediate availability
```

**Characteristics:**
- Single network hop for file access
- NFS latency affects I/O performance
- No file transfer overhead
- Files immediately available on completion

### Pulsar GCP Batch Data Flow

```
1. Job Submission
   Galaxy ──► RabbitMQ ──► Job message queued

2. VM Startup
   GCP Batch ──► Create VM with Pulsar sidecar + tool container
   Pulsar sidecar ──► Connect to RabbitMQ
   Pulsar sidecar ──► Receive job message

3. Input Staging
   Pulsar sidecar ──► Download inputs from Galaxy via RabbitMQ
   Pulsar sidecar ──► Write to local SSD

4. Job Execution
   Tool reads input ◄── Local SSD (fast)
   Tool writes output ──► Local SSD (fast)

5. Output Staging
   Pulsar sidecar ──► Read outputs from SSD
   Pulsar sidecar ──► Upload to Galaxy via RabbitMQ

6. Job Completion
   Pulsar sidecar ──► Send completion message
   Galaxy ──► Receive outputs
```

**Characteristics:**
- File transfer adds startup/completion overhead
- Local SSD provides fast I/O during execution
- Decoupled from NFS availability
- Better for I/O intensive tools

## Network Requirements

### Firewall Rules

Both runners require firewall rules to allow communication from GCP Batch VMs:

| Runner | Port | Protocol | Purpose |
|--------|------|----------|---------|
| Direct GCP Batch | 2049 | TCP/UDP | NFS file access |
| Direct GCP Batch | 111 | TCP/UDP | NFS portmapper |
| Pulsar GCP Batch | 5672 | TCP | RabbitMQ AMQP |

### Service Exposure

Both solutions use the same pattern for exposing internal services to GCP Batch VMs:

1. **Node Internal IP**: Use the Kubernetes node's internal GCP IP
2. **External IP Patch**: Add the node IP as an `externalIP` on the service
3. **Firewall Rule**: Allow traffic from GCP internal networks to K8s nodes

This avoids the need for external LoadBalancers while maintaining security within the VPC.

## Configuration Reference

### Direct GCP Batch (`job_conf.yml`)

```yaml
runners:
  gcp_batch:
    load: galaxy.jobs.runners.gcp_batch:GoogleCloudBatchJobRunner
    workers: 4
    # Authentication uses ADC from VM's attached service account
    # No service_account_file needed - uses metadata service automatically
    project_id: my-gcp-project
    region: us-east4
    service_account_email: batch-runner@my-project.iam.gserviceaccount.com
    # NFS configuration
    nfs_server: "10.150.0.X"        # Set by playbook
    nfs_path: /pvc-xxxxx            # Set by playbook
    nfs_mount_path: /galaxy/server/database
    # Network
    network: default
    subnet: default
    # Compute
    machine_type: n2-standard-4
    boot_disk_size_gb: 100
    # Container
    container_image: quay.io/galaxyproject/galaxy-min:25.1
```

### Pulsar GCP Batch (`job_conf.yml`)

```yaml
runners:
  pulsar_gcp:
    load: galaxy.jobs.runners.pulsar:PulsarGcpBatchJobRunner
    workers: 4
    # AMQP connection
    amqp_url: "pyamqp://user:pass@10.150.0.X:5672//"  # Set by playbook
    # GCP settings - Authentication uses ADC from VM's attached service account
    project_id: my-gcp-project
    region: us-east4
    machine_type: n2-standard-4
    # Storage
    ssd_name: pulsar_staging
    disk_size: 375
    # Pulsar configuration
    pulsar_container_image: galaxy/pulsar-pod-staging:0.15.0.2
    default_file_action: remote_transfer
    pulsar_app_config:
      message_queue_url: "pyamqp://user:pass@10.150.0.X:5672//"
```

## Ansible Integration

### Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `enable_gcp_batch` | `false` | Enable direct GCP Batch runner |
| `enable_pulsar_gcp_batch` | `false` | Enable Pulsar GCP Batch runner |
| `gcp_batch_region` | `us-east4` | GCP region for both runners |
| `pulsar_gcp_project_id` | `""` | GCP project (required for Pulsar) |
| `pulsar_gcp_machine_type` | `n2-standard-4` | VM machine type |
| `pulsar_gcp_disk_size` | `375` | SSD size in GB |

### Automatic Configuration

The playbook automatically:

1. **Detects node IP**: Uses `ansible_default_ipv4.address`
2. **Patches services**: Adds external IP to NFS/RabbitMQ services
3. **Retrieves credentials**: Gets RabbitMQ credentials from K8s secret
4. **Constructs URLs**: Builds NFS path and AMQP URL
5. **Updates ConfigMap**: Patches `galaxy-configs` with correct values
6. **Restarts Galaxy**: Rolls out changes to deployments

## Performance Considerations

### When to Use Direct GCP Batch

- Large input files (>1 GB)
- Sequential file access patterns
- Tools that stream data
- Workflows where files are reused across steps
- When NFS is already well-tuned

### When to Use Pulsar GCP Batch

- I/O intensive tools (many small reads/writes)
- Tools with random access patterns
- When NFS latency is a bottleneck
- Multi-cloud deployments
- When upstream Galaxy support is important

### Hybrid Approach

For optimal performance, route tools based on their I/O characteristics:

```yaml
tools:
  # Text processing → Direct GCP Batch (streaming)
  - environment: gcp_batch
    id: Cut1
  - environment: gcp_batch
    id: Sort1

  # Bioinformatics → Pulsar GCP Batch (random I/O)
  - environment: pulsar_gcp
    id: toolshed.g2.bx.psu.edu/repos/devteam/bwa/bwa_mem/.*
  - environment: pulsar_gcp
    id: toolshed.g2.bx.psu.edu/repos/iuc/samtools_.*/.*
```

## Troubleshooting

### Direct GCP Batch Issues

| Symptom | Cause | Solution |
|---------|-------|----------|
| NFS mount timeout | Firewall blocking port 2049 | Check `allow-nfs-for-batch` rule |
| Permission denied | NFS export permissions | Verify galaxy user ID matches |
| Slow file access | NFS latency | Consider Pulsar for I/O heavy tools |

### Pulsar GCP Batch Issues

| Symptom | Cause | Solution |
|---------|-------|----------|
| Connection refused | Firewall blocking port 5672 | Check `allow-rabbitmq-for-batch` rule |
| Auth failed | Wrong credentials | Verify AMQP URL in ConfigMap |
| Sidecar crash | Missing dependencies | Check Pulsar container logs |

### Diagnostic Commands

```bash
# Check GCP Batch job status
gcloud batch jobs list --location=us-east4 --project=PROJECT_ID

# Check job details
gcloud batch jobs describe JOB_NAME --location=us-east4

# Check RabbitMQ connectivity (Pulsar)
kubectl exec -n galaxy galaxy-rabbitmq-server-server-0 -c rabbitmq -- \
  rabbitmqctl list_connections

# Check NFS service (Direct)
kubectl get svc -n nfs-provisioner -o wide

# Check Galaxy job logs
kubectl logs -n galaxy deploy/galaxy-job-0 -f
```

## Security Considerations

### Service Account Permissions

The GCP service account needs:
- `roles/batch.jobsEditor` - Create/manage Batch jobs
- `roles/compute.instanceAdmin.v1` - Manage VM instances
- `roles/iam.serviceAccountUser` - Use service account
- `roles/logging.logWriter` - Write logs

### Network Security

- Firewall rules restrict access to internal GCP networks (`10.128.0.0/9`)
- Services exposed only via internal IPs
- No public endpoints required
- VPC network isolation maintained

### Credential Management

- GCP key stored as K8s secret (`gcp-batch-key`)
- RabbitMQ credentials auto-generated by operator
- AMQP URLs constructed at deploy time (not stored in values)
