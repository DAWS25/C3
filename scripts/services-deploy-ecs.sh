#!/usr/bin/env bash
set -euo pipefail

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$DIR/functions.sh"
pushd "$DIR/.." >/dev/null

echo "Script [$0] started"

TENANT_ID=${TENANT_ID:-"c3"}
ENV_ID=${ENV_ID:-"local"}
STACK_PREFIX="${TENANT_ID}-${ENV_ID}"
AWS_REGION=${AWS_REGION:-$(aws configure get region)}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}
DOMAIN_PARENT=${DOMAIN_PARENT:-"daws25.com"}
TENANT_DOMAIN=${TENANT_DOMAIN:-"${TENANT_ID}.${DOMAIN_PARENT}"}
API_DOMAIN_NAME=${API_DOMAIN_NAME:-"${ENV_ID}-api.${TENANT_DOMAIN}"}
HOSTED_ZONE_ID=${HOSTED_ZONE_ID:-${ZONE_ID:-""}}

C3_API_STACK_NAME="$STACK_PREFIX-api-stack"
C3_API_SERVICE_NAME=${C3_API_SERVICE_NAME:-"api"}
C3_API_CONTAINER_PORT=${C3_API_CONTAINER_PORT:-"10274"}
C3_API_TASK_CPU=${C3_API_TASK_CPU:-"512"}
C3_API_TASK_MEMORY=${C3_API_TASK_MEMORY:-"1024"}
C3_API_DESIRED_COUNT=${C3_API_DESIRED_COUNT:-"1"}
C3_API_ASSIGN_PUBLIC_IP=${C3_API_ASSIGN_PUBLIC_IP:-"ENABLED"}
C3_API_PATH_PATTERNS=${C3_API_PATH_PATTERNS:-"/api,/api/*"}
C3_API_HEALTH_CHECK_PATH=${C3_API_HEALTH_CHECK_PATH:-"/api"}
C3_API_HEALTH_CHECK_GRACE_PERIOD_SECONDS=${C3_API_HEALTH_CHECK_GRACE_PERIOD_SECONDS:-"30"}
C3_API_TARGET_HEALTH_CHECK_INTERVAL_SECONDS=${C3_API_TARGET_HEALTH_CHECK_INTERVAL_SECONDS:-"15"}
C3_API_TARGET_HEALTH_CHECK_TIMEOUT_SECONDS=${C3_API_TARGET_HEALTH_CHECK_TIMEOUT_SECONDS:-"5"}
C3_API_TARGET_HEALTHY_THRESHOLD_COUNT=${C3_API_TARGET_HEALTHY_THRESHOLD_COUNT:-"2"}
C3_API_TARGET_UNHEALTHY_THRESHOLD_COUNT=${C3_API_TARGET_UNHEALTHY_THRESHOLD_COUNT:-"2"}
C3_API_LISTENER_RULE_PRIORITY=${C3_API_LISTENER_RULE_PRIORITY:-"2048"}
C3_API_INDEX_MESSAGE=${C3_API_INDEX_MESSAGE:-"Welcome to C3 API on ECS"}
C3_API_REPOSITORY_URI=${C3_API_REPOSITORY_URI:-"${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/c3-api"}
C3_API_IMAGE_VERSION=${C3_API_IMAGE_VERSION:-"$(cat version.x.txt).$(cat version.y.txt).$(cat version.z.txt)"}
C3_API_IMAGE_URI=${C3_API_IMAGE_URI:-"$C3_API_REPOSITORY_URI:$C3_API_IMAGE_VERSION"}
C3_VERSION=${C3_VERSION:-"$C3_API_IMAGE_VERSION"}
C3_API_CFN_TIMEOUT_SECONDS=${C3_API_CFN_TIMEOUT_SECONDS:-"300"}

deploy_stack_safe() {
    local stack_name="$1"
    shift
    wait_for_stack_ready "$stack_name"
    if timeout "${C3_API_CFN_TIMEOUT_SECONDS}s" aws cloudformation deploy --stack-name "$stack_name" "$@"; then
        return 0
    else
        local exit_code=$?
        if [[ "$exit_code" -eq 124 ]]; then
            echo "CloudFormation deploy timed out after ${C3_API_CFN_TIMEOUT_SECONDS}s for stack $stack_name"
        fi
        return "$exit_code"
    fi
}

if [[ -z "$HOSTED_ZONE_ID" ]]; then
    R53_STACK_NAME="$TENANT_ID-r53-zone-stack"
    HOSTED_ZONE_ID=$(aws cloudformation describe-stacks \
        --stack-name "$R53_STACK_NAME" \
        --query "Stacks[0].Outputs[?OutputKey=='ZoneId'].OutputValue" \
        --output text 2>/dev/null || true)

    if [[ -z "$HOSTED_ZONE_ID" || "$HOSTED_ZONE_ID" == "None" ]]; then
        echo "HOSTED_ZONE_ID not provided and unable to resolve it from stack $R53_STACK_NAME"
        echo "Run ./scripts/tenant-deploy.sh first, or export HOSTED_ZONE_ID"
        exit 1
    fi

    echo "Resolved HostedZoneId from $R53_STACK_NAME"
fi

echo "Verifying image exists: $C3_API_IMAGE_URI"
aws ecr describe-images \
    --registry-id "$AWS_ACCOUNT_ID" \
    --region "$AWS_REGION" \
    --repository-name "c3-api" \
    --image-ids "imageTag=${C3_API_IMAGE_URI##*:}" >/dev/null

echo "Deploying api to ECS stack: $C3_API_STACK_NAME"
deploy_stack_safe "$C3_API_STACK_NAME" \
    --template-file c3-cform/service/api-ecs-service.cform.yaml \
    --parameter-overrides \
        TenantId="$TENANT_ID" \
        EnvId="$ENV_ID" \
        ApiDomainName="$API_DOMAIN_NAME" \
        HostedZoneId="$HOSTED_ZONE_ID" \
        ServiceName="$C3_API_SERVICE_NAME" \
        ContainerImageUri="$C3_API_IMAGE_URI" \
        ContainerPort="$C3_API_CONTAINER_PORT" \
        TaskCpu="$C3_API_TASK_CPU" \
        TaskMemory="$C3_API_TASK_MEMORY" \
        DesiredCount="$C3_API_DESIRED_COUNT" \
        AssignPublicIp="$C3_API_ASSIGN_PUBLIC_IP" \
        PathPatterns="$C3_API_PATH_PATTERNS" \
        HealthCheckPath="$C3_API_HEALTH_CHECK_PATH" \
        HealthCheckGracePeriodSeconds="$C3_API_HEALTH_CHECK_GRACE_PERIOD_SECONDS" \
        TargetHealthCheckIntervalSeconds="$C3_API_TARGET_HEALTH_CHECK_INTERVAL_SECONDS" \
        TargetHealthCheckTimeoutSeconds="$C3_API_TARGET_HEALTH_CHECK_TIMEOUT_SECONDS" \
        TargetHealthyThresholdCount="$C3_API_TARGET_HEALTHY_THRESHOLD_COUNT" \
        TargetUnhealthyThresholdCount="$C3_API_TARGET_UNHEALTHY_THRESHOLD_COUNT" \
        ListenerRulePriority="$C3_API_LISTENER_RULE_PRIORITY" \
        C3Version="$C3_VERSION" \
        C3IndexMessage="$C3_API_INDEX_MESSAGE"

popd >/dev/null
echo "Script [$0] completed"
