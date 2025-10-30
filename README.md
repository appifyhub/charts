# AppifyHub's Cloud Charts

This repository contains the **essential** Kubernetes (K8s) configuration and Helm chart manifests for deploying a foundational cluster infrastructure for AppifyHub's suite of services. This is a companion repository to [AppifyHub's Terraform repository](https://github.com/appifyhub/terraform).

> ⚠️ &nbsp; This setup, unchanged, is not scalable enough for production workloads.

### How to use this?

The guide is broken up over several charts, all of which are listed below. Each chart has its own README file with detailed instructions on how to install and use it.

Prerequisites:

  1. Set up a K8s cluster, for example using Appify Hub's minimal configuration from the [Terraform](https://github.com/appifyhub/terraform) repository – or create and host your own cluster any other way
  1. Install [Helm 3](https://helm.sh/docs/intro/quickstart/#install-helm) on your local machine (`helm` CLI)
  1. Install the [K8s command-line tool](https://kubernetes.io/docs/tasks/tools/#kubectl) on your local machine (`kubectl` CLI)

It's also strongly recommended that you install [`k9s`](https://k9scli.io/topics/install) for monitoring and managing your K8s cluster – it's an excellent tool that will make your life way easier.

## Installing controllers, apps and charts

Once you're connected to your K8s cluster, you can use the charts from this repository to install apps and services into it. If you're using AppifyHub's Terraform configuration, there's a `connect` script located in this directory – you can use it to quickly configure your K8s context and make sure `kubectl` works only with your desired cluster.

In order to get these local charts directly available in your Helm CLI, you can add this repository to your local Helm configuration:

```bash
# Add the AppifyHub Helm repository
helm repo add appifyhub https://charts.appifyhub.com
# Update the local Helm repository cache
helm repo update
```

To list all available charts in this repository, you can run:

```bash
# List all available charts in the AppifyHub Helm repository
helm search repo appifyhub
```

Here's a summary of which additional tools this repository offers:

#### Cluster Tools

  - [Ingress Controller and Load Balancer](./cluster-ingress/README.md): A straightforward way to expose services to the Internet using Traefik
  - [PostgreSQL Cluster](./postgres-cluster/README.md): A database cluster with a CloudNativePG operator
  - [Continuous Deployment](./continuous-deployment/README.md): A GitOps-based continuous deployment setup using ArgoCD
  - [Vault - Secrets Manager](./vault-secrets/README.md): _(not recommended)_ An advanced secrets manager for storing sensitive configuration data

#### Tests and Demos

  - [Echo Test](./echo/README.md): A simple HTTP Echo server for testing connectivity
  - [Persistence Test](./persistence-check/README.md): A simple database server for testing persistence
  - [Secrets Test (using Doppler)](./secrets-check/README.md): A simple pod that helps verify Doppler and plain secrets injection

#### App and Service Charts

  - [AppifyHub's Monolith API](./appifyhub-api/README.md): The API service from the [AppifyHub Monolith repository](https://github.com/appifyhub/monolith)
  - [The Agent's API](./the-agent-api/README.md): The service from [The Agent repository](https://github.com/appifyhub/the-agent)
  - [Workflow Automations](./n8n/README.md): The n8n workflow automation platform for connecting apps and automating workflows
  - [URL Shortener](./url-shortener/README.md): A generic URL shortener powered by Shlink
