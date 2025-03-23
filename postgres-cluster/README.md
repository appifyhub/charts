# PostgreSQL Cluster

This directory contains the **essential** Kubernetes (K8s) configuration and Helm chart manifests for deploying a foundational PostgreSQL database cluster using [CloudNative PostgreSQL](https://github.com/cloudnative-pg/cloudnative-pg) (CloudNativePG/CNPG).

> ⚠️ &nbsp; This might not be enough for your production workloads.

### How to use this?

Prerequisites:

  1. Follow the basic setup steps from the [root-level README](../README.md)

## Installing dependencies

CNPG is an all-in-one K8s toolset for deploying simple database clusters. To get started with CNPG, we need to install its Helm dependencies:

```bash
# Find and load the CNPG Helm charts
helm repo add cnpg https://cloudnative-pg.github.io/charts
helm repo update
```

## Setting up the database cluster

Let's move to the repository root for this. The first step is to install the CNPG operator which will control the new database cluster in the background. There are two ways to do this.

### 1. Using only the CNPG Helm chart _(not our way)_

```bash
# Optionally create a dedicated namespace for databases
kubectl create namespace databases
# Install the CNPG operator from the newly added repo
helm install postgres-cluster cnpg/cloudnative-pg --namespace databases
```

If you need to undo:

```bash
# Uninstall the CNPG operator
helm uninstall postgres-cluster --namespace databases
# Optionally, completely delete all CNPG-related resources
# Danger: Deleting these CRDs will remove all CNPG databases too
kubectl delete crd \
  scheduledbackups.postgresql.cnpg.io \
  subscriptions.postgresql.cnpg.io \
  backups.postgresql.cnpg.io \
  clusterimagecatalogs.postgresql.cnpg.io \
  clusters.postgresql.cnpg.io \
  databases.postgresql.cnpg.io \
  imagecatalogs.postgresql.cnpg.io \
  poolers.postgresql.cnpg.io \
  publications.postgresql.cnpg.io
# Delete the new namespace if you don't need it
kubectl delete namespace databases
```

This way does not automatically spawn database instances and only installs the CNPG operator. In a subsequent step, you will need to install the actual databases. This directory contains a Helm chart that also installs the databases, so you can use that instead.

### 2. Using the local Helm chart – recommended

This method only enables the CRDs first, then expects you to install the databases using the provided Helm chart.

```bash
# This part is the same as in the previous section
kubectl create namespace databases
helm install postgres-cluster cnpg/cloudnative-pg --namespace databases
# But then we immediately uninstall it, keeping the CRDs
helm uninstall postgres-cluster --namespace databases
```

If you need to undo:

```bash
# This part is the same as in the previous section
kubectl delete crd \
  scheduledbackups.postgresql.cnpg.io \
  subscriptions.postgresql.cnpg.io \
  backups.postgresql.cnpg.io \
  clusterimagecatalogs.postgresql.cnpg.io \
  clusters.postgresql.cnpg.io \
  databases.postgresql.cnpg.io \
  imagecatalogs.postgresql.cnpg.io \
  poolers.postgresql.cnpg.io \
  publications.postgresql.cnpg.io
kubectl delete namespace databases
```

## Installing the databases

This section assumes that you have already set up the CRDs using the second method above. Now that the cluster is prepared, you can go ahead and install the operator and databases.

**Important**: Your CNPG operator installation should have printed notes upon success. In those notes, you should have the maximum number of nodes on which you can install your database instances. For example, if you have 3 worker nodes, then the operator should have printed that 3 database instances can be installed. You don't have to follow this pattern, but you should know that a different setup might impact how K8s schedules work on your cluster, especially requests that depend on pods with database access.

There are clear benefits of having multiple database instances:

- You can have a primary instance and two replicas – great for high availability and automatic failover handling
- Different access modes through dedicated services:
  - `postgres-cluster-rw`: Read/Write endpoint (primary)
  - `postgres-cluster-ro`: Read-Only endpoint (replicas)
  - `postgres-cluster-r`: Read endpoint (all instances)
- Controlled workload scheduling:
  - Database operator runs on the control plane
  - Database instances run on the worker nodes

> ⚠️ &nbsp; Cost notice: This step allocates additional volumes for each of the database instances.

The default chart configuration installs only one instance, but you can change that number using the Helm installation command:

```bash
# Install 3 instances of the database cluster
helm install postgres-cluster ./postgres-cluster --namespace databases \
  --set cnpg.instances=3 \
  --set cnpg.auth.username=admin_username_you_want \
  --set cnpg.auth.password=admin_password_you_want \
  --set cnpg.bootstrap.database=default_database_you_want \
  --set cnpg.bootstrap.owner=default_owner_you_want
```

