#!/usr/bin/env bash
set -euo pipefail
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
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

pushd c3-cform/env

echo "## Deploying WEB BUCKET stack..."

BUCKET_STACK_NAME="$STACK_PREFIX-web-bucket-stack"
delete_stack_if_rollback_complete "$BUCKET_STACK_NAME"
aws cloudformation deploy \
    --stack-name "$BUCKET_STACK_NAME" \
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
aws cloudformation deploy \
    --stack-name "$ECS_ROLE_STACK_NAME" \
    --template-file ecs-role.cform.yaml \
    --capabilities CAPABILITY_NAMED_IAM \
    --parameter-overrides EnvId="$ENV_ID" TenantId="$TENANT_ID"

ECS_CLUSTER_STACK_NAME="$STACK_PREFIX-ecs-cluster-stack"
delete_stack_if_rollback_complete "$ECS_CLUSTER_STACK_NAME"
aws cloudformation deploy \
    --stack-name "$ECS_CLUSTER_STACK_NAME" \
    --template-file ecs-cluster.cform.yaml \
    --parameter-overrides EnvId="$ENV_ID" TenantId="$TENANT_ID"

echo "## Deploying ALB SERVICES stack..."
ALB_SERVICES_STACK_NAME="$STACK_PREFIX-alb-services-stack"
delete_stack_if_rollback_complete "$ALB_SERVICES_STACK_NAME"
aws cloudformation deploy \
    --stack-name "$ALB_SERVICES_STACK_NAME" \
    --template-file alb-services.cform.yaml \
    --parameter-overrides EnvId="$ENV_ID" TenantId="$TENANT_ID"


popd

##
echo "Script [$0] completed for ENV_ID=$ENV_ID and DOMAIN_NAME=$DOMAIN_NAME"
popd
