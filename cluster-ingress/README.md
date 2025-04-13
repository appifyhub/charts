# Cluster Ingress and Load Balancer

This directory contains the **essential** Kubernetes (K8s) configuration and Helm chart manifests for deploying a foundational cluster Load Balancer (LB), as well as the corresponding Ingress controller.

> ⚠️ &nbsp; This setup is not scalable enough for production workloads.

### How to use this?

Prerequisites:

  1. Follow the basic setup steps from the [root-level README](../README.md)

## Getting Started

[Traefik](https://traefik.io/solutions/kubernetes-ingress) provides an easy setup for an ingress controller to use in your new K8s cluster. If you already have a load balancer installed, you should not install a new Ingress and a new Load Balancer. This guide assumes you have a fresh cluster setup and demonstrates the initial setup process for Traefik.

```bash
# Find and load the Traefik Helm charts
helm repo add traefik https://traefik.github.io/charts
helm repo update
```

Before proceeding, make sure you're using the correct K8s context and environment variables. If you're using AppifyHub's foundational Terraform configuration mentioned before, you can set up your K8s CLI environment by:

   1. Locating the generated configuration scripts in that Terraform repository
   1. Executing the configuration scripts contained within to set up your K8s CLI environment

You can easily undo the environment changes by unsetting the configuration, also by using those generated configuration scripts (e.g., after you're done with making cluster changes).

Let's move to this repository's root directory. Now, assuming that your local `charts` and `terraform` repositories are adjacent, here's how to set up the environment:

```bash
# Go to the Terraform repository
cd ../terraform
# [Optional] If you just re-created the cluster, you'll need this step
rm .ssh/known_hosts
# Configure K8s tooling to use your new cluster
./setkubeconfig
# Come back to the Charts repository
cd ../charts
```

And unsetting is just as easy:

```bash
# Go back to the Terraform repository
cd ../terraform
# Reconfigure K8s tooling to stop using this cluster
./unsetkubeconfig
# Come back to the Charts repository again
cd ../charts
```

There's also a convenience `connect` script in the root directory of this repository that seamlessly traverses the directories and sets up the K8s environment to your new cluster.

## Installation Guide

Proceeding with the Traefik installation will:

  1. Create a dedicated 'traefik' namespace
  1. Install Traefik configured specifically for the cluster we set up
  1. Allow the K8s controllers to set up an external load balancer

> ⚠️ &nbsp; Cost notice: This step boots up another server instance for the external load balancer to run on. Upon deleting the load balancer, the server instance is destroyed. This may incur costs depending on your cloud provider.

First, move to the repository root. From there, this is how to install this chart:

```bash
# Set up a separate namespace for our Traefik Ingress controller
kubectl create namespace traefik
# Install this Traefik Ingress Helm chart
helm install cluster-ingress ./cluster-ingress --namespace traefik
```

If you need to undo:

```bash
# Uninstall Traefik (also destroys the load balancer server)
helm uninstall cluster-ingress --namespace traefik
# Remove the namespace
kubectl delete namespace traefik
```

If you wish to install the additional CRDs (Custom Resource Definitions) for Traefik, e.g. to be able to include Middleware components, you can do so by running the following command:

```bash
# Install the additional CRDs – mind the Traefik version
kubectl apply \
  -f https://raw.githubusercontent.com/traefik/traefik/v3.3.5/docs/content/reference/dynamic-configuration/kubernetes-crd-definition-v1.yml \
  --namespace traefik
```

### External Load Balancer

The basic setup should be done now. If you see that an external load balancer is **not** automatically created in your cloud console, you might need to check your cloud provider's documentation on how to set up a load balancer server for your K8s cluster.

In this setup, however, the external load balancer should be created automatically and your cloud console should show its IP address targeting your cluster nodes. If that didn't happen, you have a few options:

   1. Debugging: Check the logs of the Traefik pods to see if there are any errors.
   1. Rebooting all nodes: Sometimes the cloud provider's networking setup might need a reboot to recognize the new load balancer. The previosly referenced Terraform repository contains the generated Ansible configuration for doing that in one command.
   1. Reinstalling: If all else fails, you can try to uninstall and reinstall the Traefik Ingress controller, as shown above.

### Source IP and Header Forwarding

For added security, the default configuration here disables proxying and header forwarding from all IP addresses. This effectively prohibits your cluster from reading the original client IP address and headers, and only shows you internal IPs.

Once your load balancer is up and running, you may want to enable these features and configure the cluster ingress to use the proxy protocol and allow header forwarding. It is recommended to allow only trusted IPs to control IP headers, such as your load balancer or your cluster's other internal IP addresses. Having a limited trust configuration prevents clients from injecting arbitrary IP headers, which could be used to exploit the cluster (e.g., bypassing IP2Ban rules), while still allowing the load balancer to generate the real IP headers when needed.

You can allow the proxy protocol for a single IP address (e.g., your load balancer at `100.200.1.2`), a local IP range (e.g., `10.0.0.0/8`), a public IP range (e.g., `100.200.0.0/16`), or even allow it on all IPs (`0.0.0.0/0`). Allowing header proxying from all IP addresses is obviously not recommended, as it exposes your cluster to potential security risks – but it can be useful for testing.

To allow only your own network to proxy and forward headers, you could use the following command (of course, adjusting the IP ranges as needed):

```bash
# Enable forwarding and set your IPs as the only trusted IPs
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

To undo, you need to uninstall and reinstall the Traefik Ingress controller.

### Certificates

The default configuration does not include any TLS certificates. You can use the `cert-manager` Helm chart to automatically generate and manage TLS certificates for your Ingress resources, or enable Traefik's built-in Let's Encrypt support. To test the setup, let's go with the easiest option and use Traefik's built-in Let's Encrypt support.

```bash
# Enable Let's Encrypt support (make sure to set your email address and LB IP)
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
  --set-string traefik.service.annotations."load-balancer\.hetzner\.cloud/uses-proxyprotocol"=true \
  --set "traefik.additionalArguments[0]=--providers.kubernetesingress.ingressclass=traefik" \
  --set "traefik.additionalArguments[1]=--certificatesresolvers.letsencrypt.acme.email=your-email@example.com" \
  --set "traefik.additionalArguments[2]=--certificatesresolvers.letsencrypt.acme.storage=/data/acme.json" \
  --set "traefik.additionalArguments[3]=--certificatesresolvers.letsencrypt.acme.tlschallenge=true"
```
