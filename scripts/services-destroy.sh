#!/usr/bin/env bash
set -euo pipefail
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
pushd "$DIR/.."
echo "script [$0] started"
##

TENANT_ID=${TENANT_ID:-"c3"}
ENV_ID=${ENV_ID:-"local"}
STACK_PREFIX="${TENANT_ID}-${ENV_ID}"

C3_API_STACK_NAME="$STACK_PREFIX-c3-api-stack"

stack_exists() {
  local stack_name="$1"
  aws cloudformation describe-stacks --stack-name "$stack_name" >/dev/null 2>&1
}

if stack_exists "$C3_API_STACK_NAME"; then
  echo "Deleting service stack: $C3_API_STACK_NAME"
  aws cloudformation delete-stack --stack-name "$C3_API_STACK_NAME"
  aws cloudformation wait stack-delete-complete --stack-name "$C3_API_STACK_NAME"
  echo "Deleted service stack: $C3_API_STACK_NAME"
else
  echo "Skipping missing stack: $C3_API_STACK_NAME"
fi

##
popd
echo "script [$0] completed"
