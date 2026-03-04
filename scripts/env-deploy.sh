#!/usr/bin/env bash
set -euo pipefail
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
pushd "$DIR/.."
#!

BUILD_WEB=${BUILD_WEB:-"true"}

if [[ "$BUILD_WEB" == "true" ]]; then
    echo "Building C3 web application..."
    pushd c3-web >/dev/null
    if [[ ! -d node_modules ]]; then
        npm ci
    fi
    npm run build
    popd >/dev/null
fi

aws sts get-caller-identity

ENV_ID=${ENV_ID:-"c3-local"}
DOMAIN_NAME=${DOMAIN_NAME:-""}
HOSTED_ZONE_ID=${HOSTED_ZONE_ID:-${ZONE_ID:-""}}
TENANT_ID=${TENANT_ID:-"$ENV_ID"}

if [[ -z "$DOMAIN_NAME" ]]; then
    echo "DOMAIN_NAME is required"
    exit 1
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

if [[ -z "$HOSTED_ZONE_ID" ]]; then
    R53_STACK_NAME="$TENANT_ID-r53-zone-stack"
    HOSTED_ZONE_ID=$(aws cloudformation describe-stacks \
        --stack-name "$R53_STACK_NAME" \
        --query "Stacks[0].Outputs[?OutputKey=='HostedZoneId'].OutputValue" \
        --output text 2>/dev/null || true)

    if [[ -z "$HOSTED_ZONE_ID" || "$HOSTED_ZONE_ID" == "None" ]]; then
        echo "HOSTED_ZONE_ID not provided and unable to resolve it from stack $R53_STACK_NAME"
        echo "Run ./scripts/tenant-deploy.sh with DOMAIN_NAME set, or export HOSTED_ZONE_ID"
        exit 1
    fi

    echo "Resolved HostedZoneId from $R53_STACK_NAME"
fi

echo "## Deploying TENANT VPC stack..."
VPC_STACK_NAME="$ENV_ID-vpc-3ha-stack"
delete_stack_if_rollback_complete "$VPC_STACK_NAME"
aws cloudformation deploy \
    --stack-name "$VPC_STACK_NAME" \
    --template-file c3-cform/tenant/vpc-3ha.cform.yaml \
    --parameter-overrides TenantId="$ENV_ID"

pushd c3-cform/env

echo "## Deploying WEB BUCKET stack..."

BUCKET_STACK_NAME="$ENV_ID-web-bucket-stack"
delete_stack_if_rollback_complete "$BUCKET_STACK_NAME"
aws cloudformation deploy \
    --stack-name "$BUCKET_STACK_NAME" \
    --template-file web-bucket.cform.yaml \
    --parameter-overrides EnvId="$ENV_ID"

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

echo "## Deploying ACM CERT stack..."
CERT_STACK_NAME="$ENV_ID-acm-cert-stack"
delete_stack_if_rollback_complete "$CERT_STACK_NAME"
aws cloudformation deploy \
    --stack-name "$CERT_STACK_NAME" \
    --template-file acm-cert.cform.yaml \
    --parameter-overrides \
        EnvId="$ENV_ID" \
        DomainName="$DOMAIN_NAME" \
        HostedZoneId="$HOSTED_ZONE_ID"

CERTIFICATE_ARN=${CERTIFICATE_ARN:-$(aws cloudformation describe-stacks \
    --stack-name "$CERT_STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='CertificateArn'].OutputValue" \
    --output text)}

if [[ -z "$CERTIFICATE_ARN" || "$CERTIFICATE_ARN" == "None" ]]; then
  echo "Unable to resolve CertificateArn from stack $CERT_STACK_NAME"
  exit 1
fi

echo "## deploying ECS CLUSTER stack..."
delete_stack_if_rollback_complete "$ENV_ID-ecs-cluster-stack"
aws cloudformation deploy \
    --stack-name "$ENV_ID-ecs-cluster-stack" \
    --template-file ecs-cluster.cform.yaml \
    --parameter-overrides EnvId="$ENV_ID"

echo "## Deploying ALB SERVICES stack..."
delete_stack_if_rollback_complete "$ENV_ID-alb-services-stack"
aws cloudformation deploy \
    --stack-name "$ENV_ID-alb-services-stack" \
    --template-file alb-services.cform.yaml \
    --parameter-overrides EnvId="$ENV_ID"

echo "## deploying DISTRIBUTION stack..."
delete_stack_if_rollback_complete "$ENV_ID-web-distribution-stack"
aws cloudformation deploy \
    --stack-name "$ENV_ID-web-distribution-stack" \
    --template-file web-distribution.cform.yaml \
    --parameter-overrides \
        EnvId="$ENV_ID" \
        DomainName="$DOMAIN_NAME" \
        HostedZoneId="$HOSTED_ZONE_ID" \
        CertificateArn="$CERTIFICATE_ARN"


popd

#!
popd
