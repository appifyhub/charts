# Continuous Deployment

This directory contains the guide on how to achieve continuous deployment of the other services and charts included in the repository, on top of the [GitOps](https://opengitops.dev) principles and using [ArgoCD](https://argoproj.github.io/cd) as the deployment tool.

### How to use this?

Most of the prerequisites are available for exploration in the [root-level README](../README.md), but the assumption is that you already have a running cluster with at least one active service.

Prerequisites:

  1. Follow the basic setup steps from the [root-level README](../README.md)

## Installation Guide

Let's prepare the environment for the installation of ArgoCD.

```bash
# Add the ArgoCD helm repository to your Helm client
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
```

ArgoCD's Helm charts are not needed yet, but it's good to have them in place for later. Now, let's set up a dedicated namespace for ArgoCD.

```bash
# Create the namespace for ArgoCD
kubectl create namespace argocd
```

#### ArgoCD Variants

ArgoCD comes in two main flavors: `full` and `core`. In short, [the full version](https://github.com/argoproj/argo-cd/tree/master/manifests/cluster-install) comes with all ArgoCD features, including the web UI, while [the core version](https://github.com/argoproj/argo-cd/tree/master/manifests/core-install) is a lightweight version that only includes the API server and the CLI.

The **full version**, while recommended for most users, comes with a load balancer service that exposes the UI to the internet and its own TLS certificate management. Because we already have a cluster ingress controller (Traefik) and manage our own certificates automatically, using the full version comes with complications around configuring the service ingress and request routing. In addition, it is considered less secure, as it exposes the service to the public to be accessed through the ArgoCD UI.

The **core version**, on the other hand, is more suitable for users who want to manage their own TLS certificates and have a custom ingress controller in place. It's also arguably more secure, because it doesn't expose the service to the public and only allows access through the CLI. The core version is also more lightweight, as it doesn't come with the UI and other features that may not be needed for basic use cases.

There are [quirks](https://github.com/argoproj/argo-workflows/discussions/11208) with each of the installation flavors. This guide assumes you would like to use the **core version** of ArgoCD. You can switch to the full version later if you want to (with ingress customization) – but for now, let's keep it simple and use the core version.

### ArgoCD (Core) in your K8s Cluster

You can find the latest version of ArgoCD at their [releases page](https://github.com/argoproj/argo-cd/releases). As of this writing, the latest version is `v3.0.0-rc3`, but you should be able to use any `v2` or `v3` version to complete this guide. You can also fetch the latest version using the following command:

```bash
# Prints the latest version of ArgoCD
curl -s https://api.github.com/repos/argoproj/argo-cd/releases/latest \
  | grep tag_name \
  | cut -d '"' -f 4
```

Once you've decided on the version, you can download the configuration and install it in your cluster. The following command will download the chart and install it in the `argo-cd` namespace.

```bash
# Set the version of ArgoCD you want to install - useful for later use
ARGOCD_VERSION=<your_version_here>
# Install ArgoCD into the cluster
kubectl apply --namespace argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/$ARGOCD_VERSION/manifests/core-install.yaml
```

To undo the installation, run:

```bash
# Uninstall ArgoCD from the cluster
kubectl delete --namespace argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/$ARGOCD_VERSION/manifests/core-install.yaml
```

## Using ArgoCD

Once ArgoCD Core installation is done, you will have many new components in your cluster. You can verify the state of your components in the new `argocd` namespace like this:

```bash
# Check the status of the ArgoCD components
kubectl get all -n argocd
```

When all the components are ready, you can use the [ArgoCD CLI](https://argo-cd.readthedocs.io/en/stable/cli_installation) to interact with the [ArgoCD API](https://argo-cd.readthedocs.io/en/latest/developer-guide/api-docs) server. To enable that functionality, you need to set K8s context to look at the `argocd` namespace, and then login to the ArgoCD API server in "core" mode.

```bash
# Set the K8s context to look at the argocd namespace
kubectl config set-context --current --namespace=argocd
# Login to the ArgoCD API server
argocd login --core
```

You can now freely use the ArgoCD CLI to interact with the API server. Note that this modifies the previous K8s context, so you may want to set it back to the original context after you're done using ArgoCD.

### Exporting existing Helm releases

If you wish to play around with ArgoCD on your own deployments, there's a convenience script `export-helm-to-argo.sh` included next to this guide. This script pulls the Helm charts of the services you plan to deploy to ArgoCD, and then creates new ArgoCD applications for them.

The script assumes that you've been following this repository's guides. If you have a different setup, the script's context configuration is at the top of the file, and you can modify it to suit your needs.

Simply run it with `zsh` and monitor the output.

```bash
# Run the script to migrate Helm deployments to ArgoCD
./export-helm-to-argo.sh
```

Once you have the ArgoCD applications created, you can use the ArgoCD CLI to manage them. You can also use the ArgoCD Web UI to view and manage your applications.

It's possible to also apply the ArgoCD applications to your cluster using the `kubectl` command. This is useful if you want to deploy the applications to a different cluster or if you want to use a different deployment method.

```bash
# Apply all staging ArgoCD applications to your cluster
kubectl apply -f continuous-deployment/argo/staging/
# Apply all production ArgoCD applications to your cluster
kubectl apply -f continuous-deployment/argo/production/
```

> ⚠️ &nbsp; Note that you may want to uninstall your old Helm releases after applying the ArgoCD applications. This is because the Helm releases and the ArgoCD applications may redefine each other's resources (such as replica sets), and you may end up with duplicate resources in your cluster.

### ArgoCD Web UI

Installation of the "core" version of ArgoCD does not include the Web UI that is usually exposed to the outside environment. If you still want to use the UI to manage your deployments, you can have your local ArgoCD CLI spawn a minimal frontend server and access the Web UI through your browser at `localhost`. Here's how to do that.

```bash
# Port-forward the ArgoCD API server to localhost
argocd admin dashboard --namespace argocd
```

### ArgoCD Image Updater

The [ArgoCD Image Updater](https://argocd-image-updater.readthedocs.io) is a tool that automatically updates the images of your K8s resources managed by ArgoCD. It can be used to keep your deployments up to date with the latest images from your container registry, or to automatically update the images of your K8s resources when a new version of the image is available. The Image Updater can be installed as a separate component in your cluster, and it can be configured to work with your existing ArgoCD installation.

The basic installation steps are as follows:

```bash
# Install ACDIU using kubectl
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj-labs/argocd-image-updater/stable/manifests/install.yaml
```

And to uninstall it, run:

```bash
# Uninstall ACDIU from the cluster
kubectl delete -n argocd -f https://raw.githubusercontent.com/argoproj-labs/argocd-image-updater/stable/manifests/install.yaml
```
̀