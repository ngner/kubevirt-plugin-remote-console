#!/usr/bin/env bash
set -euo pipefail

# Detect CRC API endpoint
CLUSTER_API="https://api.crc.testing:6443"
# Grab the current user token
USER_TOKEN=$(oc whoami -t)

# Choose mode: "token" or "oauth"
MODE="${1:-token}"

if [[ "$MODE" == "token" ]]; then
  echo "Starting console in TOKEN mode (no login required)..."
  ./console \
    --k8s-mode=off-cluster \
    --k8s-mode-off-cluster-endpoint="${CLUSTER_API}" \
    --k8s-auth=bearer-token \
    --k8s-auth-bearer-token="${USER_TOKEN}" \
    --user-auth=disabled
elif [[ "$MODE" == "oauth" ]]; then
  echo "Starting console in OAUTH mode (login via OpenShift)..."
  ./console \
    --k8s-mode=off-cluster \
    --k8s-mode-off-cluster-endpoint="${CLUSTER_API}" \
    --user-auth=openshift
else
  echo "Unknown mode: $MODE"
  echo "Usage: $0 [token|oauth]"
  exit 1
fi