# Secrets Check

This directory contains the **essential** Kubernetes (K8s) configuration and Helm chart manifests for deploying a Secrets Check pod that helps verify [Doppler](https://doppler.com) and plain secrets injection.

### How to use this?

Prerequisites:

  1. Follow the basic setup steps from the [root-level README](../README.md)
  1. Install the [Doppler CLI](https://docs.doppler.com/docs/cli), run `doppler login` and `doppler setup` to configure your project

## Installation Guide

### Doppler Secrets Operator

Doppler uses a K8s Operator to inject secrets into your pods. This component runs in the background and injects secrets into your pods as they start. The Secrets Check pod shown here is a simple pod that helps verify that the Doppler Secrets Operator is working as expected.

Let's add the Doppler Helm repository:

```bash
helm repo add doppler https://helm.doppler.com
helm repo update
```

Next, let's install the Doppler Operator:

```bash
# Install the Doppler Operator (it will create its own namespace)
helm install doppler-operator doppler/doppler-kubernetes-operator
```

You can simply undo this installation like this:

```bash
# Uninstall the Doppler Operator
helm uninstall doppler-operator
```

When installed, you can run `kubectl get ns` to see the new namespace that the Doppler Operator created – usually `doppler-operator-system` – and you should then be able to `kubectl get all -n doppler-operator-system` to see everything running in this namespace.

#### Doppler Service Tokens

Your Doppler operator needs a Service Token to authenticate the operator with the Doppler API and fetch secrets for injection into your apps. There are two main types of tokens you can use:

  1. **Developer Token** (for testing purposes): you can use your own developer token. This is not recommended for production, but you can get it from `doppler configure get token --plain`.
  1. **Service Token**: you can create a Service Token in the Doppler Dashboard and use it. This token is per-configuration and can be rotated independently.

Before we go ahead and set the service token, you may be wondering how will the Doppler Operator know which Service Token to use in the app and what to inject. In short – we configure this too using app deployment YAMLs and K8s Secrets. We usually create a plain K8s Secret and store the Doppler Service Token inside. Doppler Operator will then pick up the value from that K8s Secret and use it. The service token secret **must be in the same namespace** as your application deployment.

Going forward, this guide assumes that you want to use the same naming and storage conventions for the secrets as we do. Let's look at the setup next – `./secrets-check/templates` is where the K8s Secrets are defined and it's a good place to start.

#### Service Token Secret vs. App Secret

If we want to expose the Doppler-managed secrets to our apps, we need to manage **two K8s Secrets**:

  1. **K8s Secret holding the Doppler Service Token** – This is a plain K8s Secret that can be stored next to the app or somewhere else in the cluster, and it exists only to expose the Service Token to the Doppler Operator (as explained above). We will create this using `kubectl` in the next step. Here's how we will name this secret's components:

      - **Name**: `doppler-token-secret-{env}`. We want to have one service token per the environments we use (local, staging, production, etc). We will place these tokens in individual K8s Secrets and expose them for the app deployment and the Doppler operator to use. Therefore, our deployed pods will be configured to look for `doppler-token-secret-local`, `doppler-token-secret-staging`, `doppler-token-secret-production`, etc.

      - **Namespace**: `{{ .Release.Namespace }}`. Wherever you are Helm-installing the app deployment, that's the namespace in which our Service Token must be too.

  1. **K8s Secret exposing app secrets to the K8s Pods** – Doppler Operator can only inject your app's secrets when it sees its own custom K8s Secret resource called `DopplerSecret`. We have a template for it in this chart too, and here's how we will name this secret's components:

      - **Name**: `{{ .Release.Name }}-doppler-secret`. By using the Helm release name here, we create a separate `DopplerSecret` resource per deployment. We reference this name in the `deployment.yaml` when attaching secrets to the pods. For example, if you run `helm install my-app ...`, the deployed pods will be looking for `my-app-doppler-secret`. This is also where the `secrets.doppler.com/reload` annotation comes in handy, allowing the Doppler Operator to link and restart the pods when any app secrets change.

      - **Namespace**: `{{ .Release.Namespace }}`. By again using the Helm release name here, we will place the `DopplerSecret` into the same namespace where the app pods are deployed.

      - **Service Token and Managed Secrets**: The `DopplerSecret` resource will also have information on where the Service Token is, as well as describe which K8s Secret to materialize and inject into the dependent pods. For this reason, all names are Helm-parametrized and kept in sync.

## Deployment and Verification

Apart from the secret configurations we are trying to test, this chart also deploys a simple `busybox` pod that will check for presence of the injected secrets. We are including 3 types of secrets for this test:

  1. Hard-coded plain text secrets defined in `./secrets-check/values.yaml` under `extraEnv`
  1. Base64-encoded, plain K8s Screts defined in `./secrets-check/templates/plain-secret.yaml`
  1. Doppler-managed secrets, injected by the Doppler Operator
      - Secret keys and values are configured in the Doppler Dashboard online
      - In `./secrets-check/values.yaml`, we choose the default project and a configuration

#### Deployment

Let's move to the repository root now. From there, we can install this chart. In this example, we'll show how to override and customize the default configuration:

```bash
# Prepare a dedicated namespace (if not already there)
kubectl create namespace delete-me
# Install the Secrets Check into the namespace
helm install secrets-check ./secrets-check --namespace delete-me \
  --set "doppler.project=appifyhub-cloud" \
  --set "doppler.config=local" \
  --set "doppler.token=dp.st.local.your-actual-token-here"
```

If you need to undo:

```bash
# Uninstall the secrets check chart
helm uninstall secrets-check --namespace delete-me
# Remove the namespace (if you don't need it anymore)
kubectl delete namespace delete-me
```

The chart should be installed now, and we should have deployed a pod that can check for the presence of the injected secrets. Note that `appifyhub-cloud` and `local` should be your own project name and configuration name from Doppler; for example, `local` could be replaced with `dev`, `staging` or `production`, depending on what you have configured in the branching strategy in Doppler. You can configure all these values in the Doppler Dashboard.

#### Verification

Let's check the environment variables in our new pod:

```bash
# View continuous logs
kubectl logs -f deployment/secrets-check -n delete-me
# Shell into the pod to run custom verifications
kubectl exec -it deployment/secrets-check -n delete-me -- sh
# When inside the container, check the environment variables
env | sort | grep TEST
```

This should show you both the Doppler-injected secrets and the test Kubernetes secrets we hard-coded for testing.
