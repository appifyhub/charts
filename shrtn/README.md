# shrtn URL Shortener

This directory contains the Kubernetes (K8s) configuration and Helm chart manifests for deploying shrtn, a self-hosted URL shortener. Learn more at [shrtn.io](https://shrtn.io) and [GitHub](https://github.com/CordlessWool/shrtn).

### How to use this?

Most of the prerequisites are available for exploration in the [root-level README](../README.md). This document will focus only on the specific steps needed to deploy shrtn.

Prerequisites:

  1. Follow the basic setup steps from the [root-level README](../README.md)
  1. You have an ingress controller set up in your cluster, such as [Traefik](https://traefik.io)
  1. You have a load balancer or an IP address that can be used to expose services
  1. You have persistent storage available in your cluster (e.g., Hetzner Cloud Volumes)
  1. You have a secrets management strategy in place, such as [Doppler](https://www.doppler.com) or manually created K8s secrets
  1. (Optional) You have a domain name that you can use to expose the service to HTTPS traffic

## Installation Guide

This URL shortener is best deployed using a Helm chart, which is located next to this guide. The chart is designed to be installed into a K8s cluster, and it will create all of the necessary resources for shrtn to run.

This chart uses SQLite as the database backend by default, which is stored in a persistent volume. This is suitable for small to medium workloads. For production environments with high availability requirements, consider using PostgreSQL or Cloudflare D1 instead (see shrtn documentation for details).

Going forward, we will assume that you want to manage secrets using [Doppler](https://www.doppler.com). If you don't want to use Doppler, you can create the secrets manually using the `kubectl create secret` command and disable Doppler via Helm value directives. More details on how Doppler manages secrets can be found in the [Secrets Check](../secrets-check/README.md) guide.

#### Required Secrets Configuration

Before deploying shrtn, you need to set up the following secrets in your Doppler project (or K8s secrets if not using Doppler):

##### Core Required Configuration

1. **`ORIGIN`** - Base URL for the public-facing site
   - Example: `http://shrtn.example.com` or `https://shrtn.example.com`
   - This is also available as a config value, but can be overridden via secrets
   - Required for proper URL generation

2. **`DATABASE_URL`** (Optional) - Database connection string
   - Default: SQLite file (`file:sqlite_file_name.db`) - stored in persistent volume
   - For PostgreSQL: `postgresql://user:password@host:5432/database`
   - For Cloudflare D1: See shrtn documentation for libSQL connection string
   - **Note**: If using PostgreSQL, include credentials here or set via secrets

For other configuration options and secrets, see the `values.yaml` file or the shortener's documentation.

### The basic setup

Let's install the chart:

```bash
# Prepare a dedicated namespace (if not already there)
kubectl create namespace delete-me
# Install the service from there
helm install shrtn appifyhub/shrtn \
  --namespace delete-me \
  --set secrets.provider="none"
```

This basic setup **does not** automatically manage your secrets, and expects you to have them provided next to your new deployment. The ORIGIN will default to the value in `values.yaml` (`http://shrtn.cloud.appifyhub.local`).

The service created here will be exposed over HTTP (not HTTPS) at `http://shrtn.cloud.appifyhub.local`. Note the `.local` top-level domain: this is a fake domain that is used for development and testing. You can change this to a real domain in the next steps. In order to access the service on this fake domain, you need to add it to your local hosts file (e.g., `/etc/hosts`), as explained in the [Echo server](../echo/README.md) guide. In the next step, we will explore adding the secrets manager and a real domain.

**Important**: Short URL redirects (like `https://shrtn.example.com/abc123`) will always work publicly - only the creation/admin interface will be restricted.

Here's how you can undo this installation if you want to start over:

```bash
# Uninstall shrtn
helm uninstall shrtn --namespace delete-me
# Remove the namespace if you don't need it anymore
kubectl delete namespace delete-me
```

> ⚠️ &nbsp; **Important**: Uninstalling the chart will also delete the persistent volume and all your shortened URLs. Make sure to backup your data before uninstalling.

### Secrets and Domains

Whether you have a real domain or use [NIP](https://nip.io) (or similar), you can choose to expose the service to HTTP traffic through your cluster's load balancer and ingress. This is generally done by creating a K8s ingress resource that will route traffic to your service – and this chart already creates that for you.

> ⚠️ &nbsp; When using a real domain, you need to make sure that the DNS records are set up correctly. This is usually done by creating an `A` record that points to the load balancer's IP address. If you are using a service like NIP, you can use a wildcard DNS record to point all subdomains to your load balancer. You can see your load balancer's IP address from the cloud provider's console.

> 💡 &nbsp; Keep in mind that your DNS and cache provider (such as [Cloudflare](https://www.cloudflare.com)) may inject TLS certificates and other security features that come from their Anycast network, especially if you use them as a proxy and not only for DNS. This setup is not a problem, but it may cause some confusion if you are not aware of it. This installation step **will not** explicitly enable TLS or HTTPS. We will explore that in a later step.

Because a configuration based on a real domain is not assumed as the default, real domains are currently not enabled in the chart's values. We can either upgrade our existing Helm release using the `helm upgrade` command with `--set` flags to include a real domain, or we can simply install the chart again with the new values. The latter is easier, so we will do that here. You can undo the previous installation first if you want to keep your cluster clean.

```bash
# Prepare a dedicated namespace (if not already there)
kubectl create namespace staging
# Install the service from there - assuming you want it in a 'staging' namespace
helm install shrtn appifyhub/shrtn \
--namespace staging \
--set app.image.tag="latest" \
--set secrets.doppler.project="shrtn-cloud" \
--set secrets.doppler.config="staging" \
--set secrets.doppler.token="dp.st.staging.your-actual-token-here" \
--set ingress.domain.base="realdomain.com" \
--set ingress.domain.prefix="shrtn" \
--set config.values.ORIGIN="http://shrtn.realdomain.com"
```

Note that this setup is also implicitly enabling Doppler's secrets manager, which will automatically inject the secrets into your pods. For more information on how to set up Doppler, check the [Secrets Check](../secrets-check/README.md) guide.

> 💡 &nbsp; The deployment is configured to reload its secrets every 5 minutes. In addition, the deployment might create multiple pods while booting up. As soon as the pod with the secrets injected is up and running, the other pod will be shut down (potentially with some logged errors). This is normal behavior.

Make sure your Doppler project contains all the required secrets (at minimum `ORIGIN`) before deploying.

### TLS and HTTPS

The configurations shown so far are not using TLS or HTTPS. This is fine for development and testing, but in production, we should always use TLS and HTTPS to secure our traffic. We will now make some changes to the chart to enable TLS and HTTPS.

```bash
# Let's upgrade our existing Helm release to include TLS and HTTPS
helm upgrade shrtn appifyhub/shrtn \
--namespace staging \
--set app.image.tag="latest" \
--set secrets.doppler.project="shrtn-cloud" \
--set secrets.doppler.config="staging" \
--set secrets.doppler.token="dp.st.staging.your-actual-token-here" \
--set ingress.domain.base="realdomain.com" \
--set ingress.domain.prefix="shrtn" \
--set config.values.ORIGIN="https://shrtn.realdomain.com" \
--set ingress.tls.enabled=true \
--set-string ingress.annotations."traefik\.ingress\.kubernetes.io/router\.entrypoints"=websecure \
--set-string ingress.annotations."traefik\.ingress\.kubernetes\.io/router\.tls"=true \
--set-string ingress.annotations."traefik\.ingress\.kubernetes\.io/router\.tls\.certresolver"=letsencrypt
```

> 💡 &nbsp; The deployment here relies on Traefik's integration with [Let's Encrypt](https://letsencrypt.org), a widely-used provider of free TLS certificates. The chart is now configured to use the `websecure` entrypoint, which is the default entrypoint for HTTPS traffic in Traefik. If you are using a different ingress controller, you need to adjust accordingly yourself.

Note that we've also updated the `ORIGIN` configuration value to use HTTPS. This is important for shortened URLs to work correctly.

It may take a few minutes for the TLS certificate to be issued and for the service to be accessible over HTTPS.

#### Additional configuration

In addition to the install values we changed above using `--set`, there are many other configuration options available in the chart (such as rollback history, resource consumption, TTL settings, etc). You can see all of them in the `values.yaml` file.

## Important Considerations

### Backups

Since shrtn uses SQLite stored in a persistent volume by default, it's critical to backup your data regularly. You can backup the persistent volume using your cloud provider's snapshot features or by using Kubernetes backup solutions like Velero.

To manually backup shrtn data:

```bash
# Get the pod name
POD_NAME=$(kubectl get pods -n staging -l app=shrtn -o jsonpath='{.items[0].metadata.name}')

# Copy the data directory from the pod
kubectl cp staging/$POD_NAME:/data ./shrtn-backup
```

### Scaling Limitations

This chart uses SQLite as the database backend by default, which means:

  - **Only 1 replica is supported** - SQLite doesn't support multiple concurrent connections from different pods
  - For high availability and horizontal scaling, you need to configure shrtn to use PostgreSQL or Cloudflare D1 instead
  - See the [shrtn documentation](https://github.com/CordlessWool/shrtn) for database setup options

### Persistent Volume

The chart creates a persistent volume of 5Gi by default. This should be sufficient for most small to medium deployments. If you're planning to:

  - Store a large number of shortened URLs
  - Keep extensive analytics data
  - Store user-generated content

You should increase the volume size by setting `--set persistence.size=10Gi` (or larger) during installation, if needed.

> ⚠️ &nbsp; **Note**: You cannot easily resize a persistent volume after creation in most cloud environments. Plan your storage needs accordingly.
