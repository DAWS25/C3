#!/usr/bin/env bash
set -euo pipefail
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
pushd "$DIR/.." >/dev/null
echo "script [$0] started"

# Usage:
#   BASE_URL=https://local.c3.daws25.com ./scripts/health-check.sh

# Try to get CloudFormation output, fallback to localhost
ENV_ID=${ENV_ID:-local}
TENANT_ID=${TENANT_ID:-"c3"}
STACK_NAME="${TENANT_ID}-${ENV_ID}-web-distribution-dns-alias-stack"
echo "Checking CloudFormation stack: $STACK_NAME"
cf_output=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --query 'Stacks[0].Outputs[0].OutputValue' --output text 2>/dev/null) || cf_output=""
if [[ -n "$cf_output" ]]; then
	BASE_URL="https://${cf_output}"
	echo "Using CloudFormation URL: $BASE_URL"
else
	LOCAL_URL="http://127.0.0.1:10274"
	BASE_URL=${BASE_URL:-"$LOCAL_URL"}
	echo "CloudFormation output not found, using default URL: $BASE_URL"
fi

check_200() {
	local path="$1"
	local url="${BASE_URL}${path}"
	local code

	code=$(curl -sS -o /dev/null -w "%{http_code}" "$url")
	if [[ "$code" != "200" ]]; then
		echo "FAIL $url -> HTTP $code"
		exit 1
	fi

	echo "OK   $url -> HTTP 200"
}

check_200 "/api"
check_200 "/kapi"
check_200 "/ebapi"

popd >/dev/null
echo "script [$0] completed"
