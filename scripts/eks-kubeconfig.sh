#!/usr/bin/env bash
set -euo pipefail

echo "Script [$0] started"

ENV_ID=${ENV_ID:-"local"}
AWS_REGION=${AWS_REGION:-$(aws configure get region)}
EKS_CLUSTER_NAME=${EKS_CLUSTER_NAME:-"${ENV_ID}-eks-cluster"}
KUBECONFIG_PATH=${KUBECONFIG_PATH:-"/tmp/${ENV_ID}-eks-kubeconfig"}

if [[ -z "$AWS_REGION" ]]; then
    echo "ERROR: AWS_REGION is required (or configure a default AWS region)"
    exit 1
fi

mkdir -p "$(dirname "$KUBECONFIG_PATH")"

echo "Updating kubeconfig for cluster $EKS_CLUSTER_NAME in region $AWS_REGION"
AWS_PAGER="" aws eks update-kubeconfig \
    --name "$EKS_CLUSTER_NAME" \
    --region "$AWS_REGION" \
    --kubeconfig "$KUBECONFIG_PATH" >/dev/null

echo "Kubeconfig written to: $KUBECONFIG_PATH"

if command -v kubectl >/dev/null 2>&1; then
    CURRENT_CONTEXT=$(KUBECONFIG="$KUBECONFIG_PATH" kubectl config current-context)
    echo "Active context in generated kubeconfig: $CURRENT_CONTEXT"
fi

echo "Run this in your shell to use it by default: export KUBECONFIG=$KUBECONFIG_PATH"
echo "Script [$0] completed"
