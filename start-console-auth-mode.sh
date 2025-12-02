#!/usr/bin/env bash

set -euo pipefail
PATH+=:/usr/bin

oc process -f scripts/oauth-client.yaml | oc apply -f -
oc get oauthclient console-oauth-client -o jsonpath='{.secret}' >scripts/console-client-secret

# Create the off-cluster-token secret if it doesn't exist
if ! oc get secret -n openshift-console off-cluster-token &>/dev/null; then
    echo "Creating off-cluster-token secret..."
    oc apply -f scripts/serviceaccount-secret.yaml
    # Wait for Kubernetes to populate the secret with token data
    echo "Waiting for secret to be populated..."
    for i in {1..30}; do
        if oc get secret -n openshift-console off-cluster-token -o jsonpath='{.data.ca\.crt}' &>/dev/null; then
            break
        fi
        sleep 1
    done
fi

oc get secret -n openshift-console off-cluster-token -o json | jq '.data."ca.crt"' -r | python3 -m base64 -d >scripts/ca.crt

npm_package_consolePlugin_name="kubevirt-plugin"
CONSOLE_IMAGE=${CONSOLE_IMAGE:="quay.io/openshift/origin-console:4.20"}
CONSOLE_PORT=${CONSOLE_PORT:=9000}

echo "Starting local OpenShift console..."

BRIDGE_BASE_ADDRESS="http://localhost:9000"
BRIDGE_USER_AUTH="openshift"
BRIDGE_K8S_MODE="off-cluster"
#BRIDGE_K8S_AUTH="openshift"
BRIDGE_CA_FILE="/tmp/ca.crt"
BRIDGE_USER_AUTH_OIDC_CLIENT_ID="console-oauth-client"
BRIDGE_USER_AUTH_OIDC_CLIENT_SECRET_FILE="/tmp/console-client-secret"
BRIDGE_USER_AUTH_OIDC_CA_FILE="/tmp/ca.crt"
BRIDGE_K8S_MODE_OFF_CLUSTER_SKIP_VERIFY_TLS=true
BRIDGE_K8S_MODE_OFF_CLUSTER_ENDPOINT=$(oc whoami --show-server)
# The monitoring operator is not always installed (e.g. for local OpenShift). Tolerate missing config maps.
set +e
#BRIDGE_K8S_MODE_OFF_CLUSTER_THANOS=$(oc -n openshift-config-managed get configmap monitoring-shared-config -o jsonpath='{.data.thanosPublicURL}' 2>/dev/null)
#BRIDGE_K8S_MODE_OFF_CLUSTER_ALERTMANAGER=$(oc -n openshift-config-managed get configmap monitoring-shared-config -o jsonpath='{.data.alertmanagerPublicURL}' 2>/dev/null)
set -e
#BRIDGE_K8S_AUTH_BEARER_TOKEN=$(oc whoami --show-token 2>/dev/null)
BRIDGE_USER_SETTINGS_LOCATION="localstorage"
CLUSTER_DOMAIN=$(oc get ingresses.config/cluster -o jsonpath={.spec.domain} 2>/dev/null)

# Customization support for local console development
# Setup customization files
CUSTOMIZATION_DIR="Console-Configuration"
MOCK_CONSOLE_CR="${CUSTOMIZATION_DIR}/mock-console-cr.json"
LOGO_FILE="${CUSTOMIZATION_DIR}/custom-logo.png"
# Fallback to scripts directory if logo not in Console-Configuration
if [ ! -f "$LOGO_FILE" ]; then
    LOGO_FILE="scripts/custom-logo.png"
fi

# Set custom logo if file exists
if [ -f "$LOGO_FILE" ]; then
    # Mount path inside container
    CONTAINER_LOGO_PATH="/tmp/custom-logo.png"
    # Format: ThemeName=/path/to/logo.png (valid themes: Dark, Light)
    BRIDGE_CUSTOM_LOGO_FILES="Dark=${CONTAINER_LOGO_PATH}"
    export BRIDGE_CUSTOM_LOGO_FILES
    echo "Custom logo found: $LOGO_FILE"
else
    echo "Warning: Custom logo file not found. Expected at: ${CUSTOMIZATION_DIR}/custom-logo.png or scripts/custom-logo.png"
fi

# Set custom product name if provided (optional)
if [ -n "${BRIDGE_CUSTOM_PRODUCT_NAME:-}" ]; then
    export BRIDGE_CUSTOM_PRODUCT_NAME
    echo "Custom product name: $BRIDGE_CUSTOM_PRODUCT_NAME"
fi

# Setup mock Console CR for perspectives customization
if [ -f "$MOCK_CONSOLE_CR" ]; then
    CONTAINER_CONSOLE_CR="/tmp/mock-console-cr.json"
    # Set environment variable for resource override
    # Format: group/version~kind~name=filepath
    # Note: Console is a cluster-scoped resource, so no namespace in the path
    BRIDGE_K8S_MODE_OFF_CLUSTER_RESOURCE_OVERRIDE="operator.openshift.io/v1~Console~cluster=${CONTAINER_CONSOLE_CR}"
    export BRIDGE_K8S_MODE_OFF_CLUSTER_RESOURCE_OVERRIDE
    echo "Mock Console CR found: $MOCK_CONSOLE_CR"
else
    echo "Warning: Mock Console CR not found at $MOCK_CONSOLE_CR. Perspectives customization will not be applied."
fi

# Don't fail if the cluster doesn't have gitops.
set +e
GITOPS_HOSTNAME=$(oc -n openshift-gitops get route cluster -o jsonpath='{.spec.host}' 2>/dev/null)
set -e
if [ -n "$GITOPS_HOSTNAME" ]; then
    BRIDGE_K8S_MODE_OFF_CLUSTER_GITOPS="https://$GITOPS_HOSTNAME"
fi

echo "API Server: $BRIDGE_K8S_MODE_OFF_CLUSTER_ENDPOINT"
echo "Console Image: $CONSOLE_IMAGE"
echo "Console URL: http://localhost:${CONSOLE_PORT}"

# Build volume mount args for customization files
volume_args=""
if [ -f "$LOGO_FILE" ]; then
    if [ "$(uname -s)" = "Linux" ]; then
        volume_args="$volume_args -v $PWD/$LOGO_FILE:${CONTAINER_LOGO_PATH}:Z"
    else
        volume_args="$volume_args -v $PWD/$LOGO_FILE:${CONTAINER_LOGO_PATH}"
    fi
fi
if [ -f "$MOCK_CONSOLE_CR" ]; then
    if [ "$(uname -s)" = "Linux" ]; then
        volume_args="$volume_args -v $PWD/$MOCK_CONSOLE_CR:${CONTAINER_CONSOLE_CR}:Z"
    else
        volume_args="$volume_args -v $PWD/$MOCK_CONSOLE_CR:${CONTAINER_CONSOLE_CR}"
    fi
fi

# Prefer podman if installed. Otherwise, fall back to docker.
if [ "$(uname -s)" = "Linux" ]; then
    # Use host networking on Linux since host.containers.internal is unreachable in some environments.
    BRIDGE_PLUGINS="${npm_package_consolePlugin_name}=http://localhost:9001"
    podman run \
        --pull missing -it --rm --network=host \
        -v $PWD/scripts/console-client-secret:/tmp/console-client-secret:Z \
        -v $PWD/scripts/ca.crt:/tmp/ca.crt:Z \
        $volume_args \
        --env BRIDGE_PLUGIN_PROXY='{"services":[{"consoleAPIPath":"/api/proxy/plugin/console-plugin-kubevirt/kubevirt-apiserver-proxy/","endpoint":"https://kubevirt-apiserver-proxy.'${CLUSTER_DOMAIN}'","authorize": true}]}' \
        --env-file <(set | grep BRIDGE | grep -v BRIDGE_K8S_AUTH_BEARER_TOKEN | grep -v BRIDGE_K8S_AUTH) \
        $CONSOLE_IMAGE
else
    BRIDGE_PLUGINS="${npm_package_consolePlugin_name}=http://host.containers.internal:9001"
    podman run \
        --pull missing --rm -p "$CONSOLE_PORT":9000 \
        -v $PWD/scripts/console-client-secret:/tmp/console-client-secret \
        -v $PWD/scripts/ca.crt:/tmp/ca.crt \
        $volume_args \
        --env BRIDGE_PLUGIN_PROXY='{"services":[{"consoleAPIPath":"/api/proxy/plugin/console-plugin-kubevirt/kubevirt-apiserver-proxy/","endpoint":"https://kubevirt-apiserver-proxy.'${CLUSTER_DOMAIN}'","authorize": true}]}' \
        --env-file <(set | grep BRIDGE | grep -v BRIDGE_K8S_AUTH_BEARER_TOKEN | grep -v BRIDGE_K8S_AUTH) \
        $CONSOLE_IMAGE
fi
