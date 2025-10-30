# URL Shortener (Shlink)

This directory contains the Kubernetes (K8s) configuration and Helm chart manifests for deploying a URL shortener powered by Shlink. Learn more at [Shlink](https://shlink.io).

### How to use this?

Most of the prerequisites are available for exploration in the [root-level README](../README.md). This document will focus only on the specific steps needed to deploy the URL shortener.

Prerequisites:

  1. Follow the basic setup steps from the [root-level README](../README.md)
  1. You have an ingress controller set up in your cluster, such as [Traefik](https://traefik.io)
  1. You have a load balancer or an IP address that can be used to expose services
  1. You have persistent storage available in your cluster (e.g., Hetzner Cloud Volumes)
  1. You have a secrets management strategy in place, such as [Doppler](https://www.doppler.com) or manually created K8s secrets
  1. (Optional) You have a domain name that you can use to expose the service to HTTPS traffic

## Installation Guide

This URL shortener is best deployed using a Helm chart, which is located next to this guide. The chart is designed to be installed into a K8s cluster, and it will create all of the necessary resources for Shlink to run.

This chart uses SQLite as the database backend by default, which is stored in a persistent volume. This is suitable for small to medium workloads. For production environments with high availability requirements, consider using PostgreSQL later (see Shlink documentation for details).

Going forward, we will assume that you want to manage secrets using [Doppler](https://www.doppler.com). If you don't want to use Doppler, you can create the secrets manually using the `kubectl create secret` command and disable Doppler via Helm value directives. More details on how Doppler manages secrets can be found in the [Secrets Check](../secrets-check/README.md) guide.

#### Required Secrets Configuration

Before deploying the URL shortener, you need to set up the following secrets in your Doppler project (or K8s secrets if not using Doppler):

1. `GEOLITE_LICENSE_KEY` — Maxmind GeoLite2 license key. See [GeoLite2 license key](https://shlink.io/documentation/geolite-license-key/).
2. `INITIAL_API_KEY` — Bootstrap API key for Shlink. See [Install via Docker](https://shlink.io/documentation/install-docker-image/).

For other configuration options and secrets, see the `values.yaml` file or the Shlink documentation.

### The basic setup

Let's install the chart:

```bash
# Prepare a dedicated namespace (if not already there)
kubectl create namespace delete-me
# Install the service from there
helm install url-shortener appifyhub/url-shortener \
  --namespace delete-me \
  --set secrets.provider="none"
```

This basic setup does not automatically manage your secrets. The `DEFAULT_DOMAIN` and `IS_HTTPS_ENABLED` values will be computed from the chart's `ingress.*` configuration by default.

The service here will typically be exposed over HTTP (TLS is terminated at Traefik/edge). In production behind Traefik/Cloudflare, set `IS_HTTPS_ENABLED=true` to ensure Shlink generates correct HTTPS links.

Here's how you can undo this installation if you want to start over:

```bash
# Uninstall the URL shortener
helm uninstall url-shortener --namespace delete-me
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
helm install url-shortener appifyhub/url-shortener \
--namespace staging \
--set app.image.tag="latest" \
--set secrets.doppler.project="url-shortener-cloud" \
--set secrets.doppler.config="staging" \
--set secrets.doppler.token="dp.st.staging.your-actual-token-here" \
--set ingress.domain.base="realdomain.com" \
--set ingress.domain.prefix="url-shortener"
```

Note that this setup is also implicitly enabling Doppler's secrets manager, which will automatically inject the secrets into your pods. For more information on how to set up Doppler, check the [Secrets Check](../secrets-check/README.md) guide.

> 💡 &nbsp; The deployment is configured to reload its secrets every 5 minutes. In addition, the deployment might create multiple pods while booting up. As soon as the pod with the secrets injected is up and running, the other pod will be shut down (potentially with some logged errors). This is normal behavior.

Make sure your Doppler project contains at least `GEOLITE_LICENSE_KEY` and `INITIAL_API_KEY` before deploying.

### TLS and HTTPS

The configurations shown so far are not using TLS or HTTPS. This is fine for development and testing, but in production, we should always use TLS and HTTPS to secure our traffic. We will now make some changes to the chart to enable TLS and HTTPS.

```bash
# Let's upgrade our existing Helm release to include TLS and HTTPS
helm upgrade url-shortener appifyhub/url-shortener \
--namespace staging \
--set app.image.tag="latest" \
--set secrets.doppler.project="url-shortener-cloud" \
--set secrets.doppler.config="staging" \
--set secrets.doppler.token="dp.st.staging.your-actual-token-here" \
--set ingress.domain.base="realdomain.com" \
--set ingress.domain.prefix="url-shortener" \
--set ingress.tls.enabled=true \
--set-string ingress.annotations."traefik\.ingress\.kubernetes\.io/router\.entrypoints"=websecure \
--set-string ingress.annotations."traefik\.ingress\.kubernetes\.io/router\.tls"=true \
--set-string ingress.annotations."traefik\.ingress\.kubernetes\.io/router\.tls\.certresolver"=letsencrypt
```

> 💡 &nbsp; The deployment here relies on Traefik's integration with [Let's Encrypt](https://letsencrypt.org), a widely-used provider of free TLS certificates. The chart is now configured to use the `websecure` entrypoint, which is the default entrypoint for HTTPS traffic in Traefik. If you are using a different ingress controller, you need to adjust accordingly yourself.

Also set `IS_HTTPS_ENABLED=true` so Shlink generates HTTPS links.


It may take a few minutes for the TLS certificate to be issued and for the service to be accessible over HTTPS.

#### Additional configuration

In addition to the install values we changed above using `--set`, there are many other configuration options available in the chart (such as rollback history, resource consumption, TTL settings, etc).

See `values.yaml` for overridable non-sensitive config and future DB/Redis toggles.

## Important Considerations

### Backups

Since Shlink uses SQLite stored in a persistent volume by default, it's critical to backup your data regularly. You can backup the persistent volume using your cloud provider's snapshot features or by using Kubernetes backup solutions like Velero.

To manually backup data:

```bash
# Get the pod name
POD_NAME=$(kubectl get pods -n staging -l app=url-shortener -o jsonpath='{.items[0].metadata.name}')

# Copy the data directory from the pod
kubectl cp staging/$POD_NAME:/etc/shlink ./url-shortener-backup
```

### Scaling Limitations

This chart uses SQLite by default, which means:

  - Only 1 replica is supported
  - For high availability and horizontal scaling, you need to move to Postgres and configure a shared Redis/Valkey for locks

### Persistent Volume

The chart creates a persistent volume of 10Gi by default. Increase via `--set persistence.size=20Gi` if needed.
