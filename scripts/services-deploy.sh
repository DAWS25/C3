#!/usr/bin/env bash
set -euo pipefail
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
pushd "$DIR/.."
echo "script [$0] started"
##

TENANT_ID=${TENANT_ID:-"c3"}
ENV_ID=${ENV_ID:-"local"}
STACK_PREFIX="${TENANT_ID}-${ENV_ID}"

stack_status() {
    local stack_name="$1"
    aws cloudformation describe-stacks \
        --stack-name "$stack_name" \
        --query 'Stacks[0].StackStatus' \
        --output text 2>/dev/null || true
}

delete_stack_if_rollback_complete() {
    local stack_name="$1"
    local status
    status=$(stack_status "$stack_name")
    if [[ "$status" == "ROLLBACK_COMPLETE" ]]; then
        echo "Deleting rollback-complete stack: $stack_name"
        aws cloudformation delete-stack --stack-name "$stack_name"
        aws cloudformation wait stack-delete-complete --stack-name "$stack_name"
    fi
}

verify_ecr_image_exists() {
    local image_uri="$1"
    local registry_host image_path repository_name image_tag image_digest
    local registry_id=""
    local aws_region=""
    local image_query_result

    if [[ "$image_uri" != */* ]]; then
        echo "ERROR: Invalid image URI (missing registry/repository): $image_uri"
        exit 1
    fi

    registry_host="${image_uri%%/*}"
    image_path="${image_uri#*/}"

    if [[ "$registry_host" =~ ^([0-9]{12})\.dkr\.ecr\.([a-z0-9-]+)\.amazonaws\.com(\.cn)?$ ]]; then
        registry_id="${BASH_REMATCH[1]}"
        aws_region="${BASH_REMATCH[2]}"
    else
        echo "ERROR: Unsupported registry host for ECR validation: $registry_host"
        echo "Expected an ECR URI like <account>.dkr.ecr.<region>.amazonaws.com/<repo>:<tag>"
        exit 1
    fi

    if [[ "$image_path" == *"@"* ]]; then
        repository_name="${image_path%@*}"
        image_digest="${image_path#*@}"
        echo "Verifying image digest exists in ECR: $repository_name@$image_digest"
        image_query_result=$(aws ecr describe-images \
            --registry-id "$registry_id" \
            --region "$aws_region" \
            --repository-name "$repository_name" \
            --image-ids "imageDigest=$image_digest" \
            --query 'imageDetails[0].imageDigest' \
            --output text 2>/dev/null || true)
    else
        repository_name="${image_path%:*}"
        image_tag="${image_path##*:}"
        if [[ "$repository_name" == "$image_path" || -z "$image_tag" ]]; then
            echo "ERROR: Image URI must include a tag or digest: $image_uri"
            exit 1
        fi
        echo "Verifying image tag exists in ECR: $repository_name:$image_tag"
        image_query_result=$(aws ecr describe-images \
            --registry-id "$registry_id" \
            --region "$aws_region" \
            --repository-name "$repository_name" \
            --image-ids "imageTag=$image_tag" \
            --query 'imageDetails[0].imageDigest' \
            --output text 2>/dev/null || true)
    fi

    if [[ -z "$image_query_result" || "$image_query_result" == "None" || "$image_query_result" == "null" ]]; then
        echo "ERROR: Image not found in ECR: $image_uri"
        exit 1
    fi

    echo "Verified image exists in ECR: $image_uri"
}


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
CFN_DEPLOY_TIMEOUT_SECONDS=${CFN_DEPLOY_TIMEOUT_SECONDS:-"1800"}
# use version files and ecr repo outpout to construct image URI, or allow override by env var for faster iterations
C3_API_REPOSITORY_URI=${C3_API_REPOSITORY_URI:-""}
if [[ -z "$C3_API_REPOSITORY_URI" ]]; then
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    AWS_REGION=$(aws configure get region)
    C3_API_REPOSITORY_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/c3-api"
fi
C3_API_IMAGE_VERSION="$(cat version.x.txt).$(cat version.y.txt).$(cat version.z.txt)"
C3_API_IMAGE_URI=${C3_API_IMAGE_URI:-"$C3_API_REPOSITORY_URI:$C3_API_IMAGE_VERSION"}
verify_ecr_image_exists "$C3_API_IMAGE_URI"
delete_stack_if_rollback_complete "$C3_API_STACK_NAME"
echo "Deploying C3 API stack: $C3_API_STACK_NAME image URI: $C3_API_IMAGE_URI timeout: ${CFN_DEPLOY_TIMEOUT_SECONDS}s"
set +e
timeout "$CFN_DEPLOY_TIMEOUT_SECONDS" aws cloudformation deploy \
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
deploy_exit_code=$?
set -e

if [[ "$deploy_exit_code" -eq 124 ]]; then
    current_status=$(stack_status "$C3_API_STACK_NAME")
    echo "ERROR: CloudFormation deploy timed out after ${CFN_DEPLOY_TIMEOUT_SECONDS}s for stack $C3_API_STACK_NAME"
    echo "Current stack status: ${current_status:-UNKNOWN}"
    exit 1
fi

if [[ "$deploy_exit_code" -ne 0 ]]; then
    echo "ERROR: CloudFormation deploy failed for stack $C3_API_STACK_NAME"
    exit "$deploy_exit_code"
fi


##
popd
echo "script [$0] completed"
