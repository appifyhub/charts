# Echo Server

This directory contains the **essential** Kubernetes (K8s) configuration and Helm chart manifests for deploying an Echo Server, a simple HTTP server that prints back the request details.

### How to use this?

Prerequisites:

  1. Follow the basic setup steps from the [root-level README](../README.md)
  1. You have an ingress controller set up in your cluster
  1. You have a load balancer or an IP address that can be used to expose services

## Install the Echo server into your cluster

Let's move to the repository root first. From there, we can install the chart:

```bash
# Prepare a dedicated namespace (if not already there)
kubectl create namespace delete-me
# Install the Echo server there
helm install echo appifyhub/echo --namespace delete-me
```

If you need to undo:

```bash
# Uninstall the echo server
helm uninstall echo --namespace delete-me
# Remove the namespace if you don't need it anymore
kubectl delete namespace delete-me
```

## Exposing the Echo server

If you are not willing to edit your real domain's DNS settings, or you don't have a domain for this project yet, you can work around that by configuring a fake domain on your local machine. To do that, you'll need your load balancer's public IP address (e.g, `123.456.789.000`). We will map a new fake domain to your load balancer's IP address in your local hosts file (e.g., `/etc/hosts`).

In this example, we're going to use `echo.appifyhub.local` as our fake domain – and here's how you can add it to your hosts file:

```console
# Default mappings
127.0.0.1       localhost
255.255.255.255 broadcasthost
::1             localhost

# Fake mappings
123.456.789.000 echo.appifyhub.local
```

Alternatively, you can use a service like [nip.io](https://nip.io) to map your IP address to a nip.io subdomain, or even edit your DNS settings to point a real domain to your load balancer's IP address.

Either way, the new domain's ingress route needs to be set within the cluster. The domain name is defined in this chart's `./echo/values.yaml` under `ingress.hosts`. You can either change this value in the Helm values and run `helm upgrade`, or you can upgrade the release with the new values using the Helm CLI and no file edits:

```bash
# Upgrade the release with the new value
helm upgrade echo appifyhub/echo --namespace delete-me \
  --set "ingress.hosts[0].host=some.other.domain.local"
```

Now your Helm release is updated with the new domain value, and the cluster is ready to serve the app on the new domain.

### Test the Echo server

> 💡 &nbsp; If you're starting Echo for the first time, it may take **a few minutes** for the load balancer to be provisioned and the DNS to propagate. The service itself also takes a while to boot up and liveness checks to pass. The service is ready when it starts emitting logs, so keep an eye on the logs.

Once the Echo pod is up and running, we move on to the final step: testing the service.

```bash
curl -v http://echo.appifyhub.local
```

This should return the request details including the client IP address, headers, etc. To test header forwarding restrictions, you can use the following command:

```bash
curl -v http://echo.appifyhub.local -H "X-Forwarded-For: 100.200.50.10"
```

Because the ingress is now configured to allow `X-Forwarded-For` only originating from your load balancer and cluster ingress, this **should not** return the request details including the `X-Forwarded-For` header (not the one you manually set).
