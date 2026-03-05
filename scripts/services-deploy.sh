#!/usr/bin/env bash
set -euo pipefail
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
pushd "$DIR/.."
echo "script [$0] started"
##

TENANT_ID=${TENANT_ID:-"c3"}
ENV_ID=${ENV_ID:-"local"}
STACK_PREFIX="${TENANT_ID}-${ENV_ID}"


# Deploy c3-api service stack in the ecs cluster stack. This is separate from the main cluster stack to allow faster iterations on the service without having to redeploy the entire cluster.
# alb is already in env, deploy task def and container using fargate stack under service dir

C3_API_STACK_NAME="$STACK_PREFIX-c3-api-stack"
C3_API_SERVICE_NAME=${C3_API_SERVICE_NAME:-"c3-api"}
C3_API_CONTAINER_PORT=${C3_API_CONTAINER_PORT:-"10274"}
C3_API_TASK_CPU=${C3_API_TASK_CPU:-"512"}
C3_API_TASK_MEMORY=${C3_API_TASK_MEMORY:-"1024"}
C3_API_DESIRED_COUNT=${C3_API_DESIRED_COUNT:-"1"}
C3_API_PATH_PATTERNS=${C3_API_PATH_PATTERNS:-"/api,/api/*"}
C3_API_LISTENER_RULE_PRIORITY=${C3_API_LISTENER_RULE_PRIORITY:-"2048"}
C3_API_INDEX_MESSAGE=${C3_API_INDEX_MESSAGE:-"Welcome to C3 API on ECS"}
# use version files and ecr repo outpout to construct image URI, or allow override by env var for faster iterations
C3_API_REPOSITORY_URI=${C3_API_REPOSITORY_URI:-""}
if [[ -z "$C3_API_REPOSITORY_URI" ]]; then
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    AWS_REGION=$(aws configure get region)
    C3_API_REPOSITORY_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/c3-api"
fi
C3_API_IMAGE_VERSION="$(cat version.x.txt).$(cat version.y.txt).$(cat version.z.txt)"
C3_API_IMAGE_URI=${C3_API_IMAGE_URI:-"$C3_API_REPOSITORY_URI:$C3_API_IMAGE_VERSION"}
echo "Deploying C3 API stack: $C3_API_STACK_NAME image URI: $C3_API_IMAGE_URI"
aws cloudformation deploy \
    --stack-name "$C3_API_STACK_NAME" \
    --template-file c3-cform/service/fargate-ecs-services.cform.yaml \
    --parameter-overrides \
        TenantId="$TENANT_ID" \
        EnvId="$ENV_ID" \
        ServiceName="$C3_API_SERVICE_NAME" \
        ContainerImageUri="$C3_API_IMAGE_URI" \
        ContainerPort="$C3_API_CONTAINER_PORT" \
        TaskCpu="$C3_API_TASK_CPU" \
        TaskMemory="$C3_API_TASK_MEMORY" \
        DesiredCount="$C3_API_DESIRED_COUNT" \
        PathPatterns="$C3_API_PATH_PATTERNS" \
        ListenerRulePriority="$C3_API_LISTENER_RULE_PRIORITY" \
        C3IndexMessage="$C3_API_INDEX_MESSAGE"


##
popd
echo "script [$0] completed"
