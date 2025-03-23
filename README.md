# AppifyHub's Cloud Charts

This repository contains the **essential** Kubernetes (K8s) configuration and Helm chart manifests for deploying a foundational cluster infrastructure for AppifyHub's suite of services. This is a companion repository to [AppifyHub's Terraform repository](https://github.com/appifyhub/terraform).

> ⚠️ &nbsp; This might not be enough for your production workloads.

### How to use this?

The guide is broken up over several charts, all of which are listed below. Each chart has its own README file with detailed instructions on how to install and use it.

Prerequisites:

  1. Set up a K8s cluster, for example using Appify Hub's minimal configuration from the [Terraform](https://github.com/appifyhub/terraform) repository – or create and host your own cluster any other way
  1. Install [Helm 3](https://helm.sh/docs/intro/quickstart/#install-helm) on your local machine (`helm` CLI)
  1. Install the [K8s command-line tool](https://kubernetes.io/docs/tasks/tools/#kubectl) on your local machine (`kubectl` CLI)

It's also strongly recommended that you install [`k9s`](https://k9scli.io/topics/install) for monitoring and managing your K8s cluster – it's an excellent tool that will make your life way easier.

## Installing controllers, apps and charts

Here's a summary of which additional tools this repository offers:

#### Core cluster components

  - [Ingress Controller and Load Balancer](./cluster-ingress/README.md): A straightforward way to expose services to the Internet using Traefik
  - [PostgreSQL Cluster](./postgres-cluster/README.md): A database cluster with a CloudNativePG operator
  - [Vault - Secrets Manager](./vault-secrets/README.md) (not recommended): An advanced secrets manager for storing sensitive configuration data
  
#### Tests and Demos

  - [Echo Test](./echo/README.md): A simple HTTP Echo server for testing connectivity
  - [Persistence Test](./persistence-check/README.md): A simple database server for testing persistence
  - [Secrets Test (using Doppler)](./secrets-check/README.md): A simple pod that helps verify Doppler and plain secrets injection
