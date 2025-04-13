#!/bin/bash

set -e # Exit on error
set -o pipefail # Propagate pipe errors

echo ""

# Check if terraform directory exists
if [ ! -d "../terraform" ]; then
  echo "❗ Sibling 'terraform' directory not found."
  echo "   Clone https://github.com/appifyhub/terraform next to these 'charts' first."
  exit 1
fi

# Check if setkubeconfig exists
if [ ! -f "../terraform/setkubeconfig" ]; then
  echo "❗ Script 'setkubeconfig' not found in '../terraform'."
  echo "   Follow the guide at https://github.com/appifyhub/terraform to generate it."
  exit 1
fi

# Change into terraform directory
cd ../terraform

# Run the config script from there
./setkubeconfig || true

# Go back to charts
cd ../charts

echo ""
echo "✅ Your cluster is now connected!"
exit 0
