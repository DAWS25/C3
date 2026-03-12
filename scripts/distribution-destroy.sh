#!/usr/bin/env bash
set -euo pipefail

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$DIR/utils_aws.sh"
pushd "$DIR/.." >/dev/null

ENV_ID=${ENV_ID:-"local"}
TENANT_ID=${TENANT_ID:-"c3"}
STACK_PREFIX="${TENANT_ID}-${ENV_ID}"
DISTRIBUTION_STACK="$STACK_PREFIX-web-distribution-stack"
DISTRIBUTION_DNS_ALIAS_STACK="$STACK_PREFIX-web-distribution-dns-stack"
DELETE_STACK_TIMEOUT_SECONDS=${DELETE_STACK_TIMEOUT_SECONDS:-1800}
DELETE_STACK_POLL_SECONDS=${DELETE_STACK_POLL_SECONDS:-30}

echo "## Destroying distribution stack for TENANT_ID=$TENANT_ID ENV_ID=$ENV_ID"

if stack_exists "$DISTRIBUTION_DNS_ALIAS_STACK"; then
	echo "Deleting stack: $DISTRIBUTION_DNS_ALIAS_STACK"
	aws cloudformation delete-stack --stack-name "$DISTRIBUTION_DNS_ALIAS_STACK"
	wait_for_stack_delete_with_timeout "$DISTRIBUTION_DNS_ALIAS_STACK" "$DELETE_STACK_TIMEOUT_SECONDS" "$DELETE_STACK_POLL_SECONDS"
	echo "Deleted stack: $DISTRIBUTION_DNS_ALIAS_STACK"
else
	echo "Skipping missing stack: $DISTRIBUTION_DNS_ALIAS_STACK"
fi

if stack_exists "$DISTRIBUTION_STACK"; then
	BUCKET_NAME=$(aws cloudformation list-stack-resources \
		--stack-name "$DISTRIBUTION_STACK" \
		--query "StackResourceSummaries[?LogicalResourceId=='DistributionBucket'].PhysicalResourceId" \
		--output text 2>/dev/null || true)

	if [[ -n "$BUCKET_NAME" && "$BUCKET_NAME" != "None" ]]; then
		echo "Emptying distribution bucket: $BUCKET_NAME"
		aws s3 rm "s3://$BUCKET_NAME" --recursive || true
	fi

	echo "Deleting stack: $DISTRIBUTION_STACK"
	aws cloudformation delete-stack --stack-name "$DISTRIBUTION_STACK"
	wait_for_stack_delete_with_timeout "$DISTRIBUTION_STACK" "$DELETE_STACK_TIMEOUT_SECONDS" "$DELETE_STACK_POLL_SECONDS"
	echo "Deleted stack: $DISTRIBUTION_STACK"
else
	echo "Skipping missing stack: $DISTRIBUTION_STACK"
fi

echo "## Distribution destroy completed for ENV_ID=$ENV_ID"

popd >/dev/null
