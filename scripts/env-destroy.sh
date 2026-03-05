#!/usr/bin/env bash
set -euo pipefail

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
pushd "$DIR/.." >/dev/null

ENV_ID=${ENV_ID:-"local"}
TENANT_ID=${TENANT_ID:-"c3"}
STACK_PREFIX="${TENANT_ID}-${ENV_ID}"

ALB_SERVICES_STACK="$STACK_PREFIX-alb-services-stack"
EKS_CLUSTER_STACK="$STACK_PREFIX-eks-cluster-stack"
EKS_ROLE_STACK="$STACK_PREFIX-eks-role-stack"
ECS_CLUSTER_STACK="$STACK_PREFIX-ecs-cluster-stack"
ECS_ROLE_STACK="$STACK_PREFIX-ecs-role-stack"
WEB_BUCKET_STACK="$STACK_PREFIX-web-bucket-stack"

stack_exists() {
	local stack_name="$1"
	aws cloudformation describe-stacks --stack-name "$stack_name" >/dev/null 2>&1
}

delete_stack_if_exists() {
	local stack_name="$1"
	if stack_exists "$stack_name"; then
		echo "Deleting stack: $stack_name"
		aws cloudformation delete-stack --stack-name "$stack_name"
		aws cloudformation wait stack-delete-complete --stack-name "$stack_name"
		echo "Deleted stack: $stack_name"
	else
		echo "Skipping missing stack: $stack_name"
	fi
}

echo "## Destroying env stacks for TENANT_ID=$TENANT_ID ENV_ID=$ENV_ID"

delete_stack_if_exists "$ALB_SERVICES_STACK"
delete_stack_if_exists "$EKS_CLUSTER_STACK"
delete_stack_if_exists "$EKS_ROLE_STACK"
delete_stack_if_exists "$ECS_CLUSTER_STACK"
delete_stack_if_exists "$ECS_ROLE_STACK"

if stack_exists "$WEB_BUCKET_STACK"; then
	BUCKET_NAME=$(aws cloudformation describe-stacks \
		--stack-name "$WEB_BUCKET_STACK" \
		--query "Stacks[0].Outputs[?OutputKey=='ResourcesBucketName'].OutputValue" \
		--output text)

	if [[ -n "$BUCKET_NAME" && "$BUCKET_NAME" != "None" ]]; then
		echo "Emptying bucket: $BUCKET_NAME"
		aws s3 rm "s3://$BUCKET_NAME" --recursive || true
	fi
fi

delete_stack_if_exists "$WEB_BUCKET_STACK"

echo "## Destroy completed for ENV_ID=$ENV_ID"

popd >/dev/null
