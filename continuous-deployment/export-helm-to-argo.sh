#!/usr/bin/env zsh

### Generates ArgoCD application manifests from existing Helm releases ###

set -e
echo ""

# Ensure we're running using zsh
if [ ! -n "$ZSH_VERSION" ]; then
    echo "❗ Error: This script requires zsh" >&2
    exit 1
fi

# Check if tools are installed
for cmd in jq kubectl helm; do
  if ! command -v $cmd &> /dev/null; then
    echo "❗ Error: $cmd is not installed."
    exit 1
  fi
done

# Splits the string on newlines and creates an array
# Usage: `OUTPUT_ARRAY=(); split_lines_to_array "$NEWLINED_STRING" OUTPUT_ARRAY`
split_lines_to_array() {
  local input="$1"
  local output=()
  local IFS_BAK=$IFS
  IFS=$'\n'
  while read -r line; do
    [[ -n "$line" ]] && output+=("$line")
  done <<< "$input"
  IFS=$IFS_BAK
  eval "$2=(\"\${output[@]}\")"
}

# Set up cluster context
NAMESPACES=("staging" "production")
OUTPUT_DIR="./continuous-deployment/argo"
HELM_REPO_URL="https://charts.appifyhub.com"
HELM_REPO_OWNER="appifyhub"
typeset -A TAG_MAP
TAG_MAP=(
  staging "latest_beta"
  production "latest"
)

# Create namespace directories
echo "Creating namespace directories in '$OUTPUT_DIR'..."
for NAMESPACE in "${NAMESPACES[@]}"; do
  mkdir -p "$OUTPUT_DIR/$NAMESPACE"
  echo "  Created '$NAMESPACE' subdirectory"
done

# Process Helm releases and create ArgoCD applications
echo "Processing Helm releases in all namespaces..."
for NAMESPACE in "${NAMESPACES[@]}"; do
  TAG="${TAG_MAP[$NAMESPACE]}"
  echo "  Now working in '$NAMESPACE' namespace. Latest tag is ':$TAG'"

  RELEASES_STR=$(helm list -n $NAMESPACE -o json | jq -r '.[].name')
  split_lines_to_array "$RELEASES_STR" RELEASES
  echo "  Found ${#RELEASES[@]} releases: [${RELEASES[@]}]"
  
  for RELEASE in "${RELEASES[@]}"; do
    # Prepare the release export
    echo "    Generating ArgoCD application for '$RELEASE'"
    CHART_INFO=$(helm list -n $NAMESPACE -f "^$RELEASE$" -o json | jq -r '.[0]')
    CHART_NAME=$(echo $CHART_INFO | jq -r '.chart' | sed 's/-[0-9].*//')
    CHART_VERSION=$(helm search repo $HELM_REPO_OWNER/$CHART_NAME --output json | jq -r '.[0].version')
    APP_YAML_FILE="$OUTPUT_DIR/$NAMESPACE/$RELEASE.yaml"
    IMAGE_VALUES=$(helm get values $RELEASE -n $NAMESPACE --all -o json)
    IMAGE_REPO=$(echo $IMAGE_VALUES | jq -r '.image.repository // .app.image.repository // empty')
    echo "      Chart: '$CHART_NAME', Release: '$RELEASE'"
    echo "      Image: '$IMAGE_REPO:$TAG'"
    echo "      Exporting app to: '$APP_YAML_FILE'"
    echo "      Exporting values to: '$APP_YAML_FILE'"

    # Process the charts to export values first
    APP_VALUES_TEMP_FILE="$OUTPUT_DIR/$NAMESPACE/$RELEASE-values.tmp.yaml"
    helm get values $RELEASE -n $NAMESPACE -o yaml > $APP_VALUES_TEMP_FILE
    APP_VALUES_CONTENT=$(sed 's/^/        /' $APP_VALUES_TEMP_FILE)
    rm $APP_VALUES_TEMP_FILE

    # Create the ArgoCD application YAML
    cat > $APP_YAML_FILE << EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: $RELEASE-$NAMESPACE-argocd
  namespace: argocd
  annotations:
    argocd-image-updater.argoproj.io/image-list: app=$IMAGE_REPO:$TAG
    argocd-image-updater.argoproj.io/app.force-update: "true"
    argocd-image-updater.argoproj.io/app.update-strategy: digest
    argocd-image-updater.argoproj.io/app.helm.image-name: app.image.repository
    argocd-image-updater.argoproj.io/app.helm.image-tag: app.image.tag
spec:
  project: default
  source:
    chart: $CHART_NAME
    repoURL: $HELM_REPO_URL
    targetRevision: $CHART_VERSION
    helm:
      values: |
$APP_VALUES_CONTENT
  destination:
    server: https://kubernetes.default.svc
    namespace: $NAMESPACE
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF
    echo "      Done processing '$RELEASE'!"
  done
  echo "    Done processing '$NAMESPACE'!"
done

echo "Finished! Make sure you have the ArgoCD Image Updater installed."
echo "  - https://argocd-image-updater.readthedocs.io"
