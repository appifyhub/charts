# Observability

This directory contains the Kubernetes (K8s) configuration and Helm chart for a lightweight, self-hosted observability stack based on [OpenObserve](https://openobserve.ai) and [OpenTelemetry](https://opentelemetry.io). The chart wraps the official OpenObserve standalone and OpenTelemetry Collector charts with reusable defaults.

### How to use this?

Most shared prerequisites are covered in the [root-level README](../README.md). This document focuses on the storage, secrets and deployment requirements specific to observability.

The chart deploys:

- 1 OpenObserve standalone pod and its web UI
- 1 OpenTelemetry Collector agent on every node for container logs and `node/pod/container` metrics
- 1 OpenTelemetry Collector cluster deployment for cluster metrics, Kubernetes events and application OTLP
- 3 official OpenObserve Kubernetes dashboards
- 1 Traefik ingress for the OpenObserve UI

## Architecture

```text
Every node                              Cluster singleton
┌─────────────────────────┐            ┌─────────────────────────┐
│ OTel agent DaemonSet    │            │ OTel cluster collector  │
│                         │            │                         │
│ • container stdout logs │            │ • cluster metrics       │
│ • host CPU/memory       │            │ • Kubernetes events     │
│ • pod/container metrics │            │ • application OTLP      │
└────────────┬────────────┘            └────────────┬────────────┘
             │ OTLP/HTTP                            │ OTLP/HTTP
             └─────────────────┬────────────────────┘
                               ▼
                    ┌──────────────────────┐
                    │ OpenObserve + UI     │
                    ├──────────────────────┤
                    │ metadata → Postgres  │
                    │ telemetry → S3       │
                    └──────────────────────┘
```

OpenObserve uses the existing CloudNativePG cluster for metadata and the existing SeaweedFS S3 endpoint for Parquet telemetry files. Its `/data` directory is an ephemeral `emptyDir` used only for short-lived WAL/cache data; the container's ephemeral-storage limit bounds it. No new PVC is needed.

A pod or node loss can discard the small WAL window that has not yet reached SeaweedFS – we accept this risk for now. The chart uses short flush intervals to bound that risk.

## Prerequisites

1. Follow the basic setup steps from the [root-level README](../README.md).
2. Install the [Doppler Kubernetes Operator](../secrets-check/README.md), or create the required K8s Secret manually.
3. Run a PostgreSQL cluster reachable from the observability namespace. The default is `postgres-cluster-rw.databases.svc.cluster.local:5432` if you haven't changed the storage chart values.
4. Run an S3-compatible store and create a dedicated bucket. The default is SeaweedFS at `http://seaweedfs-s3.storage.svc.cluster.local:8333` with bucket `openobserve` if you haven't changed any storage chart values.
5. Install an ingress controller such as [Traefik](https://traefik.io) when exposing the UI.
6. Create the PostgreSQL database/role and S3 bucket before deploying this chart.

The chart does not create either storage tenant because doing so requires privileged database and object-store credentials that the runtime pods should not have.

## Storage preparation

### PostgreSQL metadata database

Create a dedicated role and logical database on the existing cluster. Do not reuse an application's database or schema.

```sql
CREATE ROLE openobserve LOGIN PASSWORD '<strong-random-password>';
CREATE DATABASE openobserve OWNER openobserve;
```

The resulting DSN has this shape:

```text
postgresql://openobserve:<url-encoded-password>@postgres-cluster-rw.databases.svc.cluster.local:5432/openobserve
```

Store the complete DSN in Doppler as `ZO_META_POSTGRES_DSN`. Password characters with URI meaning must be URL-encoded.

### SeaweedFS telemetry bucket

Create the `openobserve` bucket with credentials that can read, write and delete objects in that bucket. For example, port-forward SeaweedFS and use an S3-compatible CLI from your workstation:

```bash
kubectl --namespace storage port-forward service/seaweedfs-s3 8333:8333

AWS_ACCESS_KEY_ID='<access-key>' \
AWS_SECRET_ACCESS_KEY='<secret-key>' \
aws --endpoint-url http://127.0.0.1:8333 s3 mb s3://openobserve
```

The default 30-day retention deletes expired telemetry through OpenObserve's compactor. Monitor SeaweedFS capacity and expand its existing volume before it fills.

## Required secrets

The default `secrets.provider=doppler` configuration expects a Doppler project named `observability` with these keys:

| Key | Purpose |
| --- | --- |
| `ZO_ROOT_USER_EMAIL` | Initial OpenObserve administrator and Collector ingestion username |
| `ZO_ROOT_USER_PASSWORD` | OpenObserve administrator and Collector ingestion password |
| `ZO_META_POSTGRES_DSN` | Dedicated PostgreSQL metadata database DSN |
| `ZO_S3_ACCESS_KEY` | SeaweedFS access key for the dedicated bucket |
| `ZO_S3_SECRET_KEY` | SeaweedFS secret key for the dedicated bucket |

Generate a separate Doppler service token for the target config and pass it as `secrets.doppler.token`. Doppler creates the `observability-secrets` K8s Secret; each component reads only the keys it needs.

If Doppler is disabled:

```yaml
secrets:
  provider: none
  managedSecretName: observability-secrets
```

Create `observability-secrets` manually with exactly the five keys above before installation.

## Configuration

Important wrapper values:

| Value | Default | Meaning |
| --- | --- | --- |
| `global.clusterName` | `kubernetes` | Cluster identity attached to every signal |
| `secrets.provider` | `doppler` | `doppler` or `none` |
| `secrets.managedSecretName` | `observability-secrets` | Secret materialized for selective component access |
| `ingress.enabled` | `true` | Expose only the OpenObserve UI |
| `ingress.domain.*` | `observability.example.com` | UI hostname |
| `openobserve.config.ZO_COMPACT_DATA_RETENTION_DAYS` | `30` | Retention for logs, metrics and traces |
| `openobserve.config.ZO_S3_*` | SeaweedFS/S3 defaults | Object-store connection and bucket |
| `dashboards.enabled` | `true` | Import the pinned Kubernetes dashboards |

The default resource requests are approximately 384 MiB memory and 150m CPU, plus 96 MiB memory and 30m CPU for each cluster node:

- OpenObserve: 100m CPU / 256Mi memory requested, 1000m / 1Gi limited
- each node Collector: 30m CPU / 96Mi memory requested, 250m / 256Mi limited
- cluster Collector: 50m CPU / 128Mi memory requested, 500m / 384Mi limited

There are no node selectors or workload placement constraints. The node Collector tolerates all taints because it must run on every node; Kubernetes schedules the other two pods normally.

## Deployment

This chart uses only pinned official images from its upstream dependencies. It does not build or require a local image.

Publish the chart through the existing chart pipeline, then install or upgrade the cluster-level Helm release directly:

```bash
helm upgrade --install observability appifyhub/observability \
  --namespace observability \
  --create-namespace \
  --set global.clusterName='<cluster-name>' \
  --set secrets.doppler.project='<doppler-project>' \
  --set secrets.doppler.config='<doppler-config>' \
  --set secrets.doppler.token='<doppler-service-token>' \
  --set ingress.domain.base='<base-domain>' \
  --set ingress.domain.prefix='<subdomain>' \
  --set ingress.tls.enabled=true \
  --set-string ingress.annotations."traefik\.ingress\.kubernetes\.io/router\.entrypoints"=websecure \
  --set-string ingress.annotations."traefik\.ingress\.kubernetes\.io/router\.tls"=true \
  --set-string ingress.annotations."traefik\.ingress\.kubernetes\.io/router\.tls\.certresolver"=letsencrypt
```

Do not commit Doppler service tokens or runtime secrets to this repository.

## OpenObserve UI

OpenObserve provides one UI for:

- logs and SQL search
- PromQL/SQL metrics exploration
- traces
- dashboards and saved views
- alerts and notification destinations

The post-install/upgrade job idempotently imports pinned upstream revisions of:

- Kubernetes / Namespaces
- Kubernetes / Namespace (Pods)
- Kubernetes / Nodes

These dashboards cover node, namespace and pod CPU, memory, disk and network usage. The chart supplies both the standard `k8s.cluster.name` resource attribute and the upstream dashboards' legacy `k8s.cluster` compatibility attribute.

An application dashboard and saved error view are intentionally not guessed before real application telemetry exists. Add them after the instrumented backend is deployed and the actual stream schema is visible. Alerts are also not provisioned until a notification destination is selected; an alert without a usable destination creates false confidence.

Container stdout appears in the `k8s_logs` stream and Kubernetes events in `k8s_events`. Application JSON records are parsed into fields while ordinary CRI/Uvicorn records remain searchable.

## Application OpenTelemetry

Instrumented applications send metrics and traces to the singleton Collector, never directly to OpenObserve:

```text
otel-cluster.observability.svc.cluster.local:4317        # OTLP/gRPC
http://otel-cluster.observability.svc.cluster.local:4318 # OTLP/HTTP
```

A typical backend deployment uses:

```yaml
env:
  - name: OTEL_SDK_DISABLED
    value: "false"
  - name: OTEL_SERVICE_NAME
    value: "<service-name>"
  - name: OTEL_EXPORTER_OTLP_ENDPOINT
    value: http://otel-cluster.observability.svc.cluster.local:4317
  - name: OTEL_EXPORTER_OTLP_PROTOCOL
    value: grpc
  - name: OTEL_LOGS_EXPORTER
    value: none
  - name: OTEL_TRACES_SAMPLER
    value: parentbased_always_on
  - name: OTEL_RESOURCE_ATTRIBUTES
    value: "deployment.environment.name=<environment>"
```

Logs continue through stdout and the node Collector; disabling the application's OTLP log exporter prevents duplication.

## Verification

After the user-managed deployment, read-only checks include:

```bash
kubectl --namespace observability get pods
kubectl --namespace observability get services
kubectl --namespace observability get jobs
kubectl --namespace observability top pods
```

Expected workloads:

- `openobserve` StatefulSet: 1 pod
- `otel-agent` DaemonSet: 1 pod per schedulable node
- `otel-cluster` Deployment: 1 pod

Open the configured UI, select the `default` organization and verify:

1. `k8s_logs` receives recent container records.
2. `k8s_events` receives Kubernetes events.
3. Kubernetes metric streams such as `k8s_node_cpu_usage` and `k8s_pod_memory_rss` exist.
4. The 3 imported dashboards return data for the configured cluster.
5. No Collector is repeatedly retrying authentication, PostgreSQL or S3 errors.

## Important considerations

### Availability

The complete observability system is intentionally in the same monitored cluster. A cluster-wide outage therefore also makes monitoring unavailable – but this is an accepted cost/simplicity trade-off for this simple cluster example and not an external uptime monitor.

### Persistence and uninstall

Chart uninstall removes OpenObserve and Collector workloads but does not remove the external PostgreSQL database or SeaweedFS objects. Deleting those persistent stores is a separate, destructive action.

OpenObserve's local `/data` is ephemeral. A restart can lose only telemetry not yet flushed to SeaweedFS; it cannot remove already persisted Parquet data or PostgreSQL metadata.

### Upgrades

The wrapper pins:

- OpenObserve standalone chart `0.92.2` / image `v0.92.2`
- OpenTelemetry Collector chart `0.172.0` / image `0.159.0`
- Official dashboards at repository revision `6e2fc4d11b844f45a25a7cfd0cf445b58424158d`

Review upstream release notes, render the complete chart and inspect configuration changes before updating these pins.
