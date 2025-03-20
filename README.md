# AppifyHub's Cloud Charts

This repository contains the **essential** Kubernetes (K8s) configuration and Helm chart manifests for deploying a foundational Appify Hub cluster infrastructure.

> ⚠️ &nbsp; Do not use for production environments.

### How to use this?

Prerequisites:

  1. Set up a cluster, for example using Appify Hub's minimal configuration from the [Terraform](https://github.com/appifyhub/terraform) repository, or create and host your own cluster
  2. Once your cluster is ready, proceed with the following steps

## Installing a Load Balancer

[Traefik](https://traefik.io/solutions/kubernetes-ingress) provides an easy setup for an ingress controller in your K8s cluster. If you already have a load balancer installed, you may skip this section. This guide assumes a fresh installation and demonstrates the Traefik setup process.

```bash
# Find and load the Traefik Helm charts
helm repo add traefik https://traefik.github.io/charts
helm repo update
```

Before proceeding, ensure you're using the correct K8s context by:

  1. Locating the generated configuration scripts in our Terraform repository
  1. Executing these configuration scripts to set up your K8s CLI environment
  1. Unset the generated configuration after you're done with making changes

Assuming that your local `charts` and `terraform` repositories are adjacent, here's how to do that:

```bash
# Go to the Terraform repository
cd ../terraform
# In case you just created the cluster, you need this
rm .ssh/known_hosts
# Configure K8s tooling to use your new cluster
./setkubeconfig
# Come back to the Charts repository
cd ../charts
```

And unsetting is just as easy:

```bash
# Go to the Terraform repository
cd ../terraform
# Reconfigure K8s tooling to stop using this cluster
./unsetkubeconfig
# Come back to the Charts repository
cd ../charts
```

Proceeding will:

  1. Create a dedicated 'traefik' namespace
  1. Install Traefik configured for our chosen cloud provider
  1. Allow the cloud provider's K8s controllers to set up an external load balancer

> ⚠️ &nbsp; Cost notice: This step boots up another server instance for the external load balancer to run on.

Here's how to execute:

```bash
# Set up a separate namespace for our LB
kubectl create namespace traefik
# Install this Traefik Ingress Helm chart
helm install cluster-ingress ./cluster-ingress --namespace traefik
```

If you need to undo:

```bash
# Uninstall Traefik (also deletes the load balancer server)
helm uninstall cluster-ingress --namespace traefik
# Remove the namespace
kubectl delete namespace traefik
```

### Source IP and Header Forwarding

For added security, the default configuration disables proxying and header forwarding from unsafe IP addresses.
Once your load balancer is up and running, you may want to enable these features and configure the cluster ingress
to allow header forwarding. It is recommended to allow these features only for trusted IPs, such as your load
balancer or your cluster's local IP addresses. This configuration prevents clients from injecting arbitrary IP
headers, which could be used to exploit the cluster (e.g., bypassing IP2Ban rules), while still allowing the
load balancer to generate the IP headers.

If needed, you can configure allowance on a local IP range (e.g., `10.0.0.0/8`), allowance on a public IP range
(e.g., `100.200.0.0/16`), or even allow all IPs (`0.0.0.0/0`) to proxy and forward headers. Allowing all IPs is
obviously not recommended as it exposes your cluster to potential security risks, but it can be useful for testing.

To allow only your own network to proxy and forward headers,
you could use the following command (adjusting IP ranges as needed):

```bash
# Enable forwarding and set your local IPs as the only trusted IPs
helm upgrade cluster-ingress ./cluster-ingress --namespace traefik \
  --set "traefik.ports.web.forwardedHeaders.enabled=true" \
  --set "traefik.ports.web.forwardedHeaders.trustedIPs[0]=10.0.0.0/8" \
  --set "traefik.ports.web.forwardedHeaders.trustedIPs[1]=100.200.0.0/16" \
  --set "traefik.ports.web.proxyProtocol.enabled=true" \
  --set "traefik.ports.web.proxyProtocol.trustedIPs[0]=10.0.0.0/8" \
  --set "traefik.ports.web.proxyProtocol.trustedIPs[1]=100.200.0.0/16" \
  --set "traefik.ports.websecure.forwardedHeaders.enabled=true" \
  --set "traefik.ports.websecure.forwardedHeaders.trustedIPs[0]=10.0.0.0/8" \
  --set "traefik.ports.websecure.forwardedHeaders.trustedIPs[1]=100.200.0.0/16" \
  --set "traefik.ports.websecure.proxyProtocol.enabled=true" \
  --set "traefik.ports.websecure.proxyProtocol.trustedIPs[0]=10.0.0.0/8" \
  --set "traefik.ports.websecure.proxyProtocol.trustedIPs[1]=100.200.0.0/16" \
  --set-string traefik.service.annotations."load-balancer\.hetzner\.cloud/uses-proxyprotocol"=true
```

## Test the setup using an Echo Server

### Install the echo server into your cluster

```bash
# Prepare a special namespace
kubectl create namespace delete-me
# Install the echo server there
helm install echo ./echo --namespace delete-me
```

If you need to undo:

```bash
# Uninstall the echo server
helm uninstall echo --namespace delete-me
# Remove the namespace
kubectl delete namespace delete-me
```

### Make the service accessible

If you are not open to editing your actual domain's DNS settings, you can cheat around this by configuring a fake domain locally. To do that, you'll need your new load balancer's IP address to your local hosts file (e.g. `/etc/hosts`). In there you need to map a fake domain to your new IP address.

In this example, we're using `echo.appifyhub.local` as our fake domain. This is defined in `echo/values.yaml`.

```console
# Default mappings
127.0.0.1       localhost
255.255.255.255 broadcasthost
::1             localhost

# Fake mappings
123.456.789.000 echo.appifyhub.local
```

#### Test the echo server

```bash
curl -v http://echo.appifyhub.local
```

This should return the request details including the requester's IP address, headers, etc.

## Test the persistence engine integration

The setup we created from the Terraform repo enables a persistent volume manager from the cloud provider.
This Container Storage Interface (CSI) driver allows us to attach persistent volumes to our pods dynamically.
We can use this feature to set up a database with a persistent volume simply by using the provided Helm chart.

> ⚠️ &nbsp; Cost notice: This step attaches a persistent volume to your cluster for the database to use.

```bash
# Prepare a special namespace (if not done already)
kubectl create namespace delete-me
# Install the persistence engine there
helm install storage-check ./storage-check --namespace delete-me
```

If you need to undo:

```bash
# Uninstall the persistence engine
helm uninstall storage-check --namespace delete-me
# Remove the namespace
kubectl delete namespace delete-me
```

### Check the persistence engine

```bash
# Connect to the database
kubectl exec -it postgres-test-0 --namespace delete-me -- psql -U postgres testdb
# Check the available tables
\dt+
# Check the database size
SELECT pg_size_pretty(pg_database_size('testdb'));
```
