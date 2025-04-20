#!/usr/bin/env zsh

# Configure DockerHub authentication for the Argo CD Image Updater

set -e
echo ""
echo "🔑  This script sets up DockerHub authentication for your ArgoCD Image Updater.\n"

NAMESPACE=argocd

# Ensure we're running using zsh
if [ ! -n "$ZSH_VERSION" ]; then
    echo "❗ Error: This script requires zsh" >&2
    exit 1
fi

# Check if tools are installed
for cmd in jq kubectl yq; do
  if ! command -v $cmd &> /dev/null; then
    echo "❗ Error: $cmd is not installed."
    exit 1
  fi
done

read "DH_USER?Enter your DockerHub username: "
read -s "DH_TOKEN?Paste your DockerHub access token (hidden input): "

# Verify credentials
echo "\nVerifying DockerHub credentials..."
TEST_URL="https://auth.docker.io/token?service=registry.docker.io&scope=repository:ratelimitpreview/test:pull"
if ! curl -s -f -u "$DH_USER:$DH_TOKEN" "$TEST_URL" > /dev/null; then
    echo "❌ Failed to authenticate with DockerHub"
    exit 1
fi

# Create DockerHub secret
echo "\nUpdating DockerHub credentials..."
TEMP_SECRET_FILE=$(mktemp)
kubectl create secret docker-registry dockerhub-secret \
    --docker-server="https://registry-1.docker.io" \
    --docker-username="$DH_USER" \
    --docker-password="$DH_TOKEN" \
    -n "$NAMESPACE" --dry-run=client -o yaml > $TEMP_SECRET_FILE

# Apply or update the secret
if kubectl get secret dockerhub-secret -n $NAMESPACE &>/dev/null; then
    echo "  Existing secret found, deleting..."
    kubectl delete secret dockerhub-secret -n $NAMESPACE
fi
kubectl apply -f $TEMP_SECRET_FILE
rm $TEMP_SECRET_FILE

# Let's create or update the Image Updater configuration
echo "\nUpdating Image Updater configuration..."
TEMP_FILE=$(mktemp)
if kubectl get configmap argocd-image-updater-config -n $NAMESPACE -o yaml > $TEMP_FILE 2>/dev/null; then
    EXISTING_CONF=$(yq eval '.data."registries.conf"' $TEMP_FILE)
    if [[ "$EXISTING_CONF" == "null" ]] || [[ -z "$EXISTING_CONF" ]]; then
        echo "  No existing configuration found. Creating a new one..."
        echo "registries:" > $TEMP_FILE.conf
    else
        echo "  Existing configuration found. Removing old docker.io config..."
        echo "$EXISTING_CONF" | yq eval 'del(.registries[] | select(.name == "docker.io"))' - > $TEMP_FILE.conf
    fi
    
    # Prepare the new configuration
    yq eval '.registries += [{
        "name": "docker.io",
        "api_url": "https://registry-1.docker.io",
        "credentials": "pullsecret:'$NAMESPACE'/dockerhub-secret",
        "default": true,
        "insecure": false
    }]' $TEMP_FILE.conf > $TEMP_FILE.new
    
    # Update configmap
    YAML_CONTENT=$(cat $TEMP_FILE.new)
    PATCH_FILE=$(mktemp)
    printf '%s' "$YAML_CONTENT" | yq eval -o=json - | \
        jq --arg content "$YAML_CONTENT" \
        '{"data": {"registries.conf": $content}}' | \
        yq eval -P - > $PATCH_FILE
    kubectl patch configmap argocd-image-updater-config -n $NAMESPACE --type=merge --patch-file $PATCH_FILE

    rm -f $PATCH_FILE
else
    # Create new configmap
    echo "No config found! Creating new Image Updater configuration..."
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-image-updater-config
  namespace: $NAMESPACE
  labels:
    app.kubernetes.io/name: argocd-image-updater-config
    app.kubernetes.io/part-of: argocd-image-updater
data:
  registries.conf: |-
    registries:
      - name: docker.io
        api_url: https://registry-1.docker.io
        credentials: pullsecret:$NAMESPACE/dockerhub-secret
        default: true
        insecure: false
EOF
fi

rm -f $TEMP_FILE $TEMP_FILE.conf $TEMP_FILE.new

# Run the verification steps
echo "\n✅ Configuration complete! We can verify now using:"
echo "   kubectl get configmap argocd-image-updater-config -n $NAMESPACE -o yaml\n"
read -q "SHOW_CONF?Would you like to see the configuration now? (y/n) "
echo ""
if [[ $SHOW_CONF == "y" || $SHOW_CONF == "Y" ]]; then
    echo "\n--- ArgoCD Image Updater Configuration ---"
    kubectl get configmap argocd-image-updater-config -n $NAMESPACE -o yaml
fi

echo "\nYou can now restart the ArgoCD Image Updater deployment to apply the changes:"
echo "   kubectl rollout restart deployment argocd-image-updater -n $NAMESPACE\n"
read -q "RESTART?Would you like to restart the deployment now? (y/n) "
echo ""
if [[ $RESTART == "y" || $RESTART == "Y" ]]; then
    kubectl rollout restart deployment argocd-image-updater -n $NAMESPACE
    echo "\n✅ Deployment restarted successfully!"
    echo "\nWaiting for deployment to stabilize..."
    kubectl rollout status deployment/argocd-image-updater -n $NAMESPACE
fi

echo "\nYou can now view the logs of the ArgoCD Image Updater to verify everything is working:"
echo "   kubectl logs -f deployment/argocd-image-updater -n $NAMESPACE\n"
read -q "SHOW_LOGS?Would you like to view the logs now? (y/n) "
echo ""
if [[ $SHOW_LOGS == "y" || $SHOW_LOGS == "Y" ]]; then
    kubectl logs -f deployment/argocd-image-updater -n $NAMESPACE
fi
