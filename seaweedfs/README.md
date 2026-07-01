# SeaweedFS – Cluster-Local S3 Storage

This directory contains the Kubernetes (K8s) configuration and Helm chart manifests for deploying [SeaweedFS](https://seaweedfs.com), an S3-compatible object storage service. This chart wraps the [official SeaweedFS Helm chart](https://github.com/seaweedfs/seaweedfs/tree/master/k8s/charts/seaweedfs) with defaults tuned for a minimal single-node setup on Hetzner Cloud.

### How to use this?

Most of the prerequisites are available for exploration in the [root-level README](../README.md). This document will focus only on the specific steps needed to deploy SeaweedFS.

Prerequisites:

  1. Follow the basic setup steps from the [root-level README](../README.md)
  1. You have persistent storage available in your cluster (e.g., Hetzner Cloud Volumes)
  1. You have generated S3 access credentials for your services

## Installation Guide

SeaweedFS is best deployed using this Helm chart, which wraps the official chart with sensible defaults. The chart creates a master server, volume server, filer, and S3 gateway — all running inside the cluster with no external exposure.

### The basic setup

```bash
# Prepare a dedicated namespace (if not already there)
kubectl create namespace storage
# Install the service from there
helm install seaweedfs appifyhub/seaweedfs \
  --namespace storage \
  --set s3Credentials.admin.accessKey="YOUR_ADMIN_ACCESS_KEY" \
  --set s3Credentials.admin.secretKey="YOUR_ADMIN_SECRET_KEY"
```

> 💡 &nbsp; Generate secure credentials with: `openssl rand -hex 20` (access key) and `openssl rand -hex 40` (secret key).

This creates a cluster-internal S3 endpoint at `http://seaweedfs-seaweedfs-s3.storage.svc.cluster.local:8333`. No ingress is created — access is restricted to pods within the cluster.

Optionally add a read-only user for services that should only consume files:

```bash
helm install seaweedfs appifyhub/seaweedfs \
  --namespace storage \
  --set s3Credentials.admin.accessKey="ADMIN_KEY" \
  --set s3Credentials.admin.secretKey="ADMIN_SECRET" \
  --set s3Credentials.readOnly.accessKey="READONLY_KEY" \
  --set s3Credentials.readOnly.secretKey="READONLY_SECRET"
```

Here's how you can undo this installation if you want to start over:

```bash
# Uninstall SeaweedFS
helm uninstall seaweedfs --namespace storage
# Remove the namespace if you don't need it anymore
kubectl delete namespace storage
```

> ⚠️ &nbsp; **Important**: Uninstalling the chart does not delete PVCs. Remove them manually if you want to reclaim storage.

### Connecting from other services

From any pod in the cluster, configure your S3 client with:

| Setting | Value |
|---------|-------|
| Endpoint | `http://seaweedfs-seaweedfs-s3.storage.svc.cluster.local:8333` |
| Region | `us-east-1` (any value works, SeaweedFS ignores it) |
| Access Key | The admin access key set during install |
| Secret Key | The admin secret key set during install |
| Path Style | `true` (required) |

### Secrets management

S3 credentials are passed at install time via `--set` flags. Store them in your consuming app's secrets manager (e.g., Doppler) so your services can connect to SeaweedFS.

The SeaweedFS chart itself does not use Doppler directly because the S3 gateway requires a structured JSON config file rather than environment variables.

### File TTL

Upload files with automatic expiration by creating buckets with a default TTL in `values.yaml`:

```yaml
seaweedfs:
  s3:
    createBuckets:
      - name: temp-files
        ttl: 7d
      - name: permanent-files
```

### Pre-signed URLs

Generate time-bound URLs for temporary external access using any S3 SDK's `generate_presigned_url` method. The URL contains a cryptographic signature and expiry timestamp — no further auth is needed on the consumer side. This is useful for sharing files with external services or giving users temporary access to specific files.

## Important Considerations

### Storage

The chart creates persistent volumes for the master (10Gi), volume server (10Gi), and filer (10Gi) using the `hcloud-volumes` storage class (Hetzner minimum is 10Gi). The volume server is where your actual file data lives.

To increase storage at install time:

```bash
--set seaweedfs.volume.dataDirs[0].size="50Gi"
```

> ⚠️ &nbsp; **Note**: You cannot easily resize a persistent volume after creation in most cloud environments. Plan your storage needs accordingly.

### Scaling Limitations

This chart is configured for a single-node setup (1 replica each for master, volume, filer, and S3 gateway). This is sufficient for small to medium workloads. For production environments requiring high availability, increase the replica counts and configure replication in `values.yaml`.

### Resource Requirements

The default resource limits are conservative:

  - Master: 16m–250m CPU, 48–256Mi memory
  - Volume: 16m–500m CPU, 48–512Mi memory
  - Filer: 16m–500m CPU, 56–512Mi memory
  - S3 Gateway: 16m–250m CPU, 48–256Mi memory

Monitor your pods' resource usage and adjust accordingly.

#### Additional configuration

In addition to the install values above, there are many other configuration options available in the chart (such as replication, volume size limits, garbage collection thresholds, etc). You can see all of them in the `values.yaml` file and the [official SeaweedFS Helm chart documentation](https://github.com/seaweedfs/seaweedfs/tree/master/k8s/charts/seaweedfs).
