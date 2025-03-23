# Secrets Manager

This directory contains the **essential** Kubernetes (K8s) configuration and Helm chart manifests for deploying HashiCorp Vault Secrets Operator using the official [HashiCorp Vault](https://developer.hashicorp.com/vault) charts.

> ⚠️ &nbsp; This might not be enough for your production workloads.

### How to use this?

Prerequisites:

  1. Follow the basic setup steps from the [root-level README](../README.md)
  1. You have an ingress controller set up in your cluster
  1. You have a load balancer or an IP address that can be used to expose services

## Installation Guide

Vault requires the HashiCorp Helm repository. To get started, we need to add this repository:

```bash
# Add the HashiCorp Helm Repository
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update
```

### Setting up Vault

The installation process sets up Vault's two main components:

  1. The Vault Secrets Operator (VSO) – manages Vault resources in Kubernetes
  1. A Vault instance – the actual secrets manager

This configuration installs a non-HA Vault instance with a single replica. For production workloads, you should consider setting up a highly available (HA) Vault cluster. To continue, let's move to the repository root first. From there, we can install the chart:

```bash
# Create a dedicated namespace for vault
kubectl create namespace vault
# Install the Vault Secrets Operator
helm install vault-secrets ./vault-secrets --namespace vault
```

If you need to undo:

```bash
# Uninstall the Vault Secrets Operator
helm uninstall vault-secrets --namespace vault
# Optionally delete the CRDs
kubectl delete crd \
  vaultauthmethods.secrets.hashicorp.com \
  vaultconnections.secrets.hashicorp.com \
  vaultpkimounts.secrets.hashicorp.com \
  vaultpkisecrets.secrets.hashicorp.com \
  vaultsecrets.secrets.hashicorp.com \
  vaultstaticsecrets.secrets.hashicorp.com
# Delete the namespace (if you don't need it anymore)
kubectl delete namespace vault
```

### Accessing Vault

First-time setup will not run the Vault unseal process. You need to do this manually. To unseal the Vault instance, you can use the following command:

```bash
# Get the Vault pod name (or manually find it in the pod list)
VAULT_POD=$(kubectl get pods -n vault -l app.kubernetes.io/name=vault -o jsonpath='{.items[0].metadata.name}')
# Unseal the Vault instance
kubectl exec -n vault $VAULT_POD -- vault operator init
```

This command will return five unseal keys and a root token. You can use the root token to authenticate with Vault. To unseal the Vault instance and get it ready, you need to run the following command:

```bash
# Unseal the Vault instance
kubectl exec -n vault $VAULT_POD -- vault operator unseal <UNSEAL_KEY>
```

You'll need to run this command three times in a row now to unseal the Vault instance, each time using a different unseal key. After this is complete, you should be able to access Vault through its various interfaces:

  - Kubernetes Service: `vault.vault.svc.cluster.local`
  - REST API: Available through the Kubernetes service
  - UI: If enabled, accessible via port-forwarding (`service/vault-ui 8200:8200`)
  - CLI: You can use the `vault` CLI tool to interact with the server

Unfortunately, Vault requires unsealing every time it starts up. For production workloads, you should consider setting up an auto-unseal mechanism via a cloud provider's KMS or HashiCorp's [auto-unseal](https://learn.hashicorp.com/tutorials/vault/autounseal-transit) feature.
