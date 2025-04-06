# Persistence Server

This directory contains the **essential** Kubernetes (K8s) configuration and Helm chart manifests for deploying an Persistence Server, a simple database server for testing persistence features of the cluster.

### How to use this?

Prerequisites:

  1. Follow the basic setup steps from the [root-level README](../README.md)

## Installation Guide

This guide assumes that you have been following AppifyHub's basic setup steps since the foundational Terraform repository. The setup we have from there has already installed a persistence manager and integrated it with the cloud provider.

This Container Storage Interface (CSI) driver allows us to attach persistent volumes to our pods **dynamically**. We can now use this feature to set up a database with a persistent volume by simply deploying the provided Helm chart. This service will be our testing ground.

> ⚠️ &nbsp; Cost notice: This step attaches a new persistent volume to your cluster for the database to use. After deleting, the volume is detached and deleted. This may incur costs depending on your cloud provider.

Let's move to the repository root first. From there, we can install the chart:

```bash
# Prepare a special namespace (if not done already)
kubectl create namespace delete-me
# Install the service there
helm install persistence-check ./persistence-check --namespace delete-me
```

If you need to undo:

```bash
# Uninstall the service
helm uninstall persistence-check --namespace delete-me
# Remove the namespace (if not needed anymore)
kubectl delete namespace delete-me
```

## Verifying the configuration

Now that the service is configured, we can check if the database is working as expected. First, we should check if the Persistence Volume (PV) and Persistence Volume Claim (PVC) have been created successfully by the CSI.

```bash
# Check the PVs
kubectl get pv
kubectl get pv --namespace delete-me
# Check the PVCs
kubectl get pvc
kubectl get pvc --namespace delete-me
```

Once PVs are created and PVCs are bound, you should see a new volume in your cloud provider's storage dashboard. This volume is attached to the database pod and will persist even if the pod is deleted. This dependency will enable the creation of the chart's StatefulSet test pod with a persistent volume. We can now verify that the setup works by connecting to the database and checking the available tables and the database size.

```bash
# Connect to the database, assuming the pod's name is 'postgres-test-0'
kubectl exec -it postgres-test-0 --namespace delete-me -- psql -U postgres testdb
# Check the available tables in PSQL
\dt+
# Check the database size in PSQL
SELECT pg_size_pretty(pg_database_size('testdb'));
```

If you see the output of the tables query (even if it's "no tables") and you see the database size, the database is working as expected. You can now use this service to load-test persistence or check other database features in your cluster. Once done, it's safe to uninstall the service and remove the namespace as mentioned above.
