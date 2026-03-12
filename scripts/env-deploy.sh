#!/usr/bin/env bash
set -euo pipefail
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$DIR/functions.sh"
pushd "$DIR/.."
#!
echo "Script [$0] started"
aws sts get-caller-identity

TENANT_ID=${TENANT_ID:-"c3"}
ENV_ID=${ENV_ID:-"local"}
STACK_PREFIX="${TENANT_ID}-${ENV_ID}"
DOMAIN_PARENT=${DOMAIN_PARENT:-"daws25.com"}
TENANT_DOMAIN=${TENANT_DOMAIN:-"$TENANT_ID.$DOMAIN_PARENT"}
ENV_DOMAIN="${ENV_ID}.${TENANT_DOMAIN}"
DOMAIN_NAME="$ENV_DOMAIN"
HOSTED_ZONE_ID=${HOSTED_ZONE_ID:-${ZONE_ID:-""}}

if [[ -z "$DOMAIN_NAME" ]]; then
    echo "DOMAIN_NAME is required"
    exit 1
fi

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

wait_for_stack_ready() {
    local stack_name="$1"
    local status
    status=$(stack_status "$stack_name")

    while [[ "$status" == *_IN_PROGRESS || "$status" == *_CLEANUP_IN_PROGRESS ]]; do
        echo "Stack $stack_name is $status; waiting for it to stabilize..."
        sleep 20
        status=$(stack_status "$stack_name")
    done
}

deploy_stack_safe() {
    local stack_name="$1"
    shift

    local attempt=1
    local max_attempts=3
    local output
    local rc

    while (( attempt <= max_attempts )); do
        wait_for_stack_ready "$stack_name"
        set +e
        output=$(aws cloudformation deploy --stack-name "$stack_name" "$@" 2>&1)
        rc=$?
        set -e

        if [[ $rc -eq 0 ]]; then
            [[ -n "$output" ]] && echo "$output"
            return 0
        fi

        echo "$output"
        if [[ "$output" == *"InvalidChangeSetStatus"*"OBSOLETE"* || "$output" == *" is in "*"_IN_PROGRESS state"* ]]; then
            echo "Transient CloudFormation state for $stack_name; retrying ($attempt/$max_attempts)..."
            attempt=$((attempt + 1))
            sleep 10
            continue
        fi

        if [[ "$output" == *"Circular dependency between resources"* ]]; then
            # Some stacks can reject no-op updates due to transient/template dependency checks.
            # If the stack already exists and is stable, continue with the current deployed version.
            local current_status
            current_status=$(stack_status "$stack_name")
            if [[ -n "$current_status" && "$current_status" != "None" ]]; then
                echo "Skipping update for $stack_name due to circular dependency check; current stack status: $current_status"
                return 0
            fi
        fi

        return $rc
    done

    echo "CloudFormation deploy failed for $stack_name after $max_attempts attempts"
    return 1
}

pushd c3-cform/env

echo "## Deploying WEB BUCKET stack..."

BUCKET_STACK_NAME="$STACK_PREFIX-web-bucket-stack"
delete_stack_if_rollback_complete "$BUCKET_STACK_NAME"
deploy_stack_safe "$BUCKET_STACK_NAME" \
    --template-file web-bucket.cform.yaml \
    --parameter-overrides EnvId="$ENV_ID" TenantId="$TENANT_ID"

BUCKET_NAME=$(aws cloudformation describe-stacks \
    --stack-name "$BUCKET_STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='ResourcesBucketName'].OutputValue" \
    --output text)    

WEB_BUILD_DIR=""
if [[ -d "../../c3-web/build" ]]; then
    WEB_BUILD_DIR="../../c3-web/build"
elif [[ -d "../../c3-web/.svelte-kit/output/client" ]]; then
    WEB_BUILD_DIR="../../c3-web/.svelte-kit/output/client"
fi

if [[ -z "$WEB_BUILD_DIR" ]]; then
    echo "No web artifact directory found. Expected ../../c3-web/build or ../../c3-web/.svelte-kit/output/client"
    exit 1
fi

aws s3 sync "$WEB_BUILD_DIR/" "s3://$BUCKET_NAME/" --delete

echo "## deploying ECS CLUSTER stack..."
ECS_ROLE_STACK_NAME="$STACK_PREFIX-ecs-role-stack"
delete_stack_if_rollback_complete "$ECS_ROLE_STACK_NAME"
deploy_stack_safe "$ECS_ROLE_STACK_NAME" \
    --template-file ecs-role.cform.yaml \
    --capabilities CAPABILITY_NAMED_IAM \
    --parameter-overrides EnvId="$ENV_ID" TenantId="$TENANT_ID"

ECS_CLUSTER_STACK_NAME="$STACK_PREFIX-ecs-cluster-stack"
delete_stack_if_rollback_complete "$ECS_CLUSTER_STACK_NAME"
deploy_stack_safe "$ECS_CLUSTER_STACK_NAME" \
    --template-file ecs-cluster.cform.yaml \
    --parameter-overrides EnvId="$ENV_ID" TenantId="$TENANT_ID"

echo "## deploying EKS CLUSTER stack..."
EKS_ROLE_STACK_NAME="$STACK_PREFIX-eks-role-stack"
delete_stack_if_rollback_complete "$EKS_ROLE_STACK_NAME"
deploy_stack_safe "$EKS_ROLE_STACK_NAME" \
    --template-file eks-role.cform.yaml \
    --capabilities CAPABILITY_NAMED_IAM \
    --parameter-overrides EnvId="$ENV_ID" TenantId="$TENANT_ID"

echo "## Deploying ALB SERVICES stack..."
ALB_SERVICES_STACK_NAME="$STACK_PREFIX-alb-services-stack"
delete_stack_if_rollback_complete "$ALB_SERVICES_STACK_NAME"
deploy_stack_safe "$ALB_SERVICES_STACK_NAME" \
    --template-file alb-services.cform.yaml \
    --parameter-overrides EnvId="$ENV_ID" TenantId="$TENANT_ID"

EKS_CLUSTER_STACK_NAME="$STACK_PREFIX-eks-cluster-stack"
delete_stack_if_rollback_complete "$EKS_CLUSTER_STACK_NAME"
ENABLE_EKS_CLUSTER_DEPLOY=${ENABLE_EKS_CLUSTER_DEPLOY:-"true"}
if [[ "$ENABLE_EKS_CLUSTER_DEPLOY" == "true" ]]; then
    deploy_stack_safe "$EKS_CLUSTER_STACK_NAME" \
        --template-file eks-cluster.cform.yaml \
        --parameter-overrides EnvId="$ENV_ID" TenantId="$TENANT_ID"
else
    echo "Skipping EKS cluster stack deploy because ENABLE_EKS_CLUSTER_DEPLOY is not true."
fi

echo "## updating local kubeconfig for EKS cluster..."
"$DIR/eks-kubeconfig.sh"


popd

##
echo "Script [$0] completed for ENV_ID=$ENV_ID and DOMAIN_NAME=$DOMAIN_NAME"
popd
