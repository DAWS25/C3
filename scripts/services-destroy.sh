#!/usr/bin/env bash
set -euo pipefail
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$DIR/utils_aws.sh"
pushd "$DIR/.."
echo "script [$0] started"
##

TENANT_ID=${TENANT_ID:-"c3"}
ENV_ID=${ENV_ID:-"local"}
STACK_PREFIX="${TENANT_ID}-${ENV_ID}"

C3_API_STACK_NAME="$STACK_PREFIX-api-stack"
KAPI_STACK_NAME="$STACK_PREFIX-kapi-stack"
KAPI_SERVICE_NAME=${KAPI_SERVICE_NAME:-"kapi"}
KAPI_NAMESPACE=${KAPI_NAMESPACE:-"default"}
KAPI_EKS_CLUSTER_NAME=${KAPI_EKS_CLUSTER_NAME:-"${ENV_ID}-eks-cluster"}
DELETE_STACK_TIMEOUT_SECONDS=${DELETE_STACK_TIMEOUT_SECONDS:-1800}
DELETE_STACK_POLL_SECONDS=${DELETE_STACK_POLL_SECONDS:-30}

if stack_exists "$C3_API_STACK_NAME"; then
  echo "Deleting service stack: $C3_API_STACK_NAME"
  aws cloudformation delete-stack --stack-name "$C3_API_STACK_NAME"
  wait_for_stack_delete_with_timeout "$C3_API_STACK_NAME" "$DELETE_STACK_TIMEOUT_SECONDS" "$DELETE_STACK_POLL_SECONDS"
  echo "Deleted service stack: $C3_API_STACK_NAME"
else
  echo "Skipping missing stack: $C3_API_STACK_NAME"
fi

if stack_exists "$KAPI_STACK_NAME"; then
  echo "Deleting service stack: $KAPI_STACK_NAME"
  aws cloudformation delete-stack --stack-name "$KAPI_STACK_NAME"
  wait_for_stack_delete_with_timeout "$KAPI_STACK_NAME" "$DELETE_STACK_TIMEOUT_SECONDS" "$DELETE_STACK_POLL_SECONDS"
  echo "Deleted service stack: $KAPI_STACK_NAME"
else
  echo "Skipping missing stack: $KAPI_STACK_NAME"
fi

if command -v kubectl >/dev/null 2>&1; then
  AWS_REGION=$(aws configure get region)
  if aws eks describe-cluster --name "$KAPI_EKS_CLUSTER_NAME" --region "$AWS_REGION" >/dev/null 2>&1; then
    echo "Deleting kapi workload from EKS cluster: $KAPI_EKS_CLUSTER_NAME"
    AWS_PAGER="" aws eks update-kubeconfig --name "$KAPI_EKS_CLUSTER_NAME" --region "$AWS_REGION" >/dev/null || true
    kubectl -n "$KAPI_NAMESPACE" delete service "$KAPI_SERVICE_NAME" --ignore-not-found=true || true
    kubectl -n "$KAPI_NAMESPACE" delete deployment "$KAPI_SERVICE_NAME" --ignore-not-found=true || true
  fi
fi

##
popd
echo "script [$0] completed"
