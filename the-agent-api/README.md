# The Agent's API

This directory contains the Kubernetes (K8s) configuration and Helm chart manifests for deploying The Agent's API service. The service's source code is available in ["The Agent" repository](https://github.com/appifyhub/the-agent).

### How to use this?

Most of the prerequisites are available for exploration in the [root-level README](../README.md). This document will focus only on the specific steps needed to deploy The Agent's API service.

Prerequisites:

  1. Follow the basic setup steps from the [root-level README](../README.md)
  1. You have an ingress controller set up in your cluster, such as [Traefik](https://traefik.io)
  1. You have a load balancer or an IP address that can be used to expose services
  1. You have a database set up and running, such as [CNPG](https://cloudnative-pg.io) or [PostgreSQL](https://www.postgresql.org)
  1. You have a secrets management strategy in place, such as [Doppler](https://www.doppler.com) or manually created K8s secrets
  1. (Optional) You have a domain name that you can use to expose the service to HTTPS traffic

## Installation Guide

The Agent's API service is best deployed using a Helm chart, which is located next to this guide. The chart is designed to be installed into a K8s cluster, and it will create _almost all_ of the necessary resources for the API service to run.

As mentioned in the prequisites, you need to have a database set up and running, and you need to have your secrets ready for the pods to use. The chart will not create the database for you or manage your K8s secrets. You need to at least have a K8s secret with the database connection string and other necessary secrets before installing the chart. For the list of all needed secrets, check the [service repository's](https://github.com/appifyhub/the-agent) Docker directory. This guide comes with sensible defaults, but those should be changed to match your environment.

Going forward, we will assume that you have the database set up and running, but you want to manage secrets using [Doppler](https://www.doppler.com). If you don't want to use Doppler, you can create the secrets manually using the `kubectl create secret` command and disable Doppler via Helm value directives. More details on how Doppler manages secrets can be found in the [Secrets Check](../secrets-check/README.md) guide.

#### Keystores

There are two ways to manage the keystore required by the service for signing JWT tokens:

  1. Using a K8s secret (or a secrets manager like Doppler) to inject the keystore into the service
  1. Using a file mounted into the service's pod

This guide and this chart assume that you will use the first option. The second option is not recommended for production environments, as it requires a file to be mounted into the pod, which is not a good practice for security reasons.

In order to use the first option, your keystore file (usually a `.jks` file or a `.p12` file) should be stored in a K8s secret `KEYSTORE_BASE64`, in base64 format. The deployment chart will automatically boot up an "init container" with an ephemeral volume where we will decode and store the keystore file. The init container will then copy the keystore file from the K8s secret into the ephemeral volume, and the main container will use that volume to access the keystore file.

### The basic setup

Let's move to the repository root first. From there, we can install the chart:

```bash
# Prepare a dedicated namespace (if not already there)
kubectl create namespace delete-me
# Install the service from there
helm install the-agent appifyhub/the-agent-api \
  --namespace delete-me \
  --set secrets.provider="none"
```

This basic setup **does not** automatically manage your secrets, and expects you to have them provided next to your new deployment. If you don't have the necessary secrets injected into your pods, you will see an error message like this:

```console
$ 2025-01-01T00:00:00.001Z Database connection attempt 1 failed.
| Retrying in 5 seconds...
```

The sevice created here will be exposed over HTTP (not HTTPS) at `http://agent.cloud.appifyhub.local`. Note the `.local` top-level domain: this is a fake domain that is used for development and testing. You can change this to a real domain in the next steps. In order to access the service on this fake domain, you need to add it to your local hosts file (e.g., `/etc/hosts`), as explained in the [Echo server](../echo/README.md) guide. In the next step, we will explore adding the secrets manager and a real domain.

Here's how you can undo this installation if you want to start over:

```bash
# Uninstall the service
helm uninstall the-agent --namespace delete-me
# Remove the namespace if you don't need it anymore
kubectl delete namespace delete-me
```

### Secrets and Domains

Whether you have a real domain or use [NIP](https://nip.io) (or similar), you can choose to expose the service to HTTP traffic through your cluster's load balancer and ingress. This is generally done by creating a K8s ingress resource that will route traffic to your service – and this chart already creates that for you.

> ⚠️ &nbsp; When using a real domain, you need to make sure that the DNS records are set up correctly. This is usually done by creating an `A` record that points to the load balancer's IP address. If you are using a service like NIP, you can use a wildcard DNS record to point all subdomains to your load balancer. You can see your load balancer's IP address from the cloud provider's console.

> 💡 &nbsp; Keep in mind that your DNS and cache provider (such as [Cloudflare](https://www.cloudflare.com)) may inject TLS certificates and other security features that come from their Anycast network, especially if you use them as a proxy and not only for DNS. This setup is not a problem, but it may cause some confusion if you are not aware of it. This installation step **will not** explicitly enable TLS or HTTPS. We will explore that in a later step.

Because a configuration based on a real domain is not assumed as the default, real domains are currently not enabled in the chart's values. We can either upgrade our existing Helm release using the `helm upgrade` command with `--set` flags to include a real domain, or we can simply install the chart again with the new values. The latter is easier, so we will do that here. You can undo the previous installation first if you want to keep your cluster clean.

```bash
# Prepare a dedicated namespace (if not already there)
kubectl create namespace staging
# Install the service from there - assuming you want it in a 'staging' namespace
helm install the-agent appifyhub/the-agent-api \
--namespace staging \
--set app.image.tag="latest_beta" \
--set secrets.doppler.project="the-agent-cloud" \
--set secrets.doppler.config="staging" \
--set secrets.doppler.token="dp.st.staging.your-actual-token-here" \
--set ingress.domain.base="realdomain.com" \
--set ingress.domain.prefix="staging.subdomain" \
--set config.values.VERBOSE="false" \
--set config.values.LOG_TG_UPDATE="false"
```

Note that this setup is also implicitly enabling Doppler's secrets manager, which will automatically inject the secrets into your pods. For more information on how to set up Doppler, check the [Secrets Check](../secrets-check/README.md) guide.

> 💡 &nbsp; The deployment is configured to reload its secrets every 5 minutes. In addition, the deployment might create multiple pods while booting up. As soon as the pod with the secrets injected is up and running, the other pod will be shut down (potentially with some logged errors). This is normal behavior.

The `config.values.VERBOSE` and `config.values.LOG_TG_UPDATE` values are optional and can be used to configure the logging level for the service. The default values are more permissive, and you should probably have them set to less permissive values in production (like we do here).

### TLS and HTTPS

The configurations shown so far are not using TLS or HTTPS. This is fine for development and testing, but in production, we should always use TLS and HTTPS to secure our traffic. We will now make some changes to the chart to enable TLS and HTTPS.

> ⚠️ &nbsp; We want high availability from our services, so we are setting the number of replicas to 2 (as an example). It's not likely that you will need it for staging configurations and it is definitely not a requirement, but it is a good practice to have at least 2 replicas in production – so this is a good opportunity to learn how to set it up.

```bash
# Let's upgrade our existing Helm release to include TLS and HTTPS
helm upgrade the-agent appifyhub/the-agent-api \
--namespace staging \
--set app.replicas=2 \
--set app.image.tag="latest_beta" \
--set secrets.doppler.project="the-agent-cloud" \
--set secrets.doppler.config="staging" \
--set secrets.doppler.token="dp.st.staging.your-actual-token-here" \
--set ingress.domain.base="realdomain.com" \
--set ingress.domain.prefix="staging.subdomain" \
--set config.values.VERBOSE="false" \
--set config.values.LOG_TG_UPDATE="false" \
--set ingress.tls.enabled=true \
--set-string ingress.annotations."traefik\.ingress\.kubernetes\.io/router\.entrypoints"=websecure \
--set-string ingress.annotations."traefik\.ingress\.kubernetes\.io/router\.tls"=true \
--set-string ingress.annotations."traefik\.ingress\.kubernetes\.io/router\.tls\.certresolver"=letsencrypt
```

> 💡 &nbsp; The deployment here relies on Traefik's integration with [Let's Encrypt](https://letsencrypt.org), a widely-used provider of free TLS certificates. The chart is now configured to use the `websecure` entrypoint, which is the default entrypoint for HTTPS traffic in Traefik. If you are using a different ingress controller, you need to adjust accordingly yourself.

It may take a few minutes for the TLS certificate to be issued and for the service to be accessible over HTTPS.

#### Additional configuration

In addition to the install values we changed above using `--set`, there are many other configuration options available in the chart (such as rollback history, open telemetry and prometheus configurations, liveness probes, resource consumption, etc). You can see all of them in the `values.yaml` file.
