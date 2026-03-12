#!/usr/bin/env bash
set -euo pipefail
DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
pushd "$DIR/.."
echo "Script[$0] started"
##

TENANT_ID=${TENANT_ID:-"c3"}
DOMAIN_PARENT=${DOMAIN_PARENT:-"daws25.com"}
TENANT_DOMAIN=${TENANT_DOMAIN:-"$TENANT_ID.$DOMAIN_PARENT"}
ECR_SCAN_ON_PUSH=${ECR_SCAN_ON_PUSH:-"true"}
ECR_SIGNING_ENABLED=${ECR_SIGNING_ENABLED:-"true"}
ECR_SIGNING_STACK_NAME=${ECR_SIGNING_STACK_NAME:-"${TENANT_ID}-ecr-signing-stack"}
ECR_SIGNING_PROFILE_NAME=${ECR_SIGNING_PROFILE_NAME:-"${TENANT_ID}_signing_profile"}
ECR_SIGNING_PROFILE_NAME="${ECR_SIGNING_PROFILE_NAME//[^[:alnum:]_]/_}"
ECR_SIGNING_PROFILE_NAME="${ECR_SIGNING_PROFILE_NAME:0:64}"
if [[ ${#ECR_SIGNING_PROFILE_NAME} -lt 2 ]]; then
    ECR_SIGNING_PROFILE_NAME="c3_signing_profile"
fi

if [[ -z "$TENANT_DOMAIN" ]]; then
    echo "TENANT_DOMAIN is required"
    exit 1
fi

echo "Deploying tenant with TENANT_ID=$TENANT_ID and TENANT_DOMAIN=$TENANT_DOMAIN"

stack_status() {
    local stack_name="$1"
    aws cloudformation describe-stacks \
        --stack-name "$stack_name" \
        --query 'Stacks[0].StackStatus' \
        --output text 2>/dev/null || true
}

wait_for_stack_ready() {
    local stack_name="$1"
    local status
    status=$(stack_status "$stack_name")

    while [[ "$status" == *_IN_PROGRESS || "$status" == *_CLEANUP_IN_PROGRESS ]]; do
        echo "Stack $stack_name is $status; waiting for it to stabilize..."
        sleep 20
        status=$(stack_status "$stack_name")
    done

    if [[ "$status" == "ROLLBACK_COMPLETE" ]]; then
        echo "Deleting rollback-complete stack $stack_name before redeploy"
        aws cloudformation delete-stack --stack-name "$stack_name"
        aws cloudformation wait stack-delete-complete --stack-name "$stack_name"
    fi
}

deploy_stack_safe() {
    local stack_name="$1"
    shift
    wait_for_stack_ready "$stack_name"
    aws cloudformation deploy --stack-name "$stack_name" "$@"
}

TENANT_ZONE_ID=$(aws route53 list-hosted-zones-by-name --dns-name "$TENANT_DOMAIN" --query "HostedZones[0].Id" --output text | sed 's/\/hostedzone\///')
if [[ -n "$TENANT_ZONE_ID" && "$TENANT_ZONE_ID" != "None" ]]; then
    echo "Route53 zone for $TENANT_DOMAIN already exists with ID $TENANT_ZONE_ID"
else
    echo "Creating Route53 hosted zone for $TENANT_DOMAIN"
    R53_STACK_NAME="$TENANT_ID-r53-zone-stack"
    deploy_stack_safe "$R53_STACK_NAME" \
        --template-file c3-cform/tenant/r53-zone.cform.yaml \
        --parameter-overrides TenantId="$TENANT_ID" DomainName="$TENANT_DOMAIN"
fi

TENANT_ZONE_ID=$(aws route53 list-hosted-zones-by-name --dns-name "$TENANT_DOMAIN" --query "HostedZones[0].Id" --output text | sed 's/\/hostedzone\///')
if [[ -z "$TENANT_ZONE_ID" || "$TENANT_ZONE_ID" == "None" ]]; then
    echo "Unable to resolve Route53 hosted zone id for $TENANT_DOMAIN"
    exit 1
fi

# Lookup PARENT_ZONE_ID by searching route53 zones for one that matches the DOMAIN_PARENT. This is used to create a delegation from the parent domain name.
PARENT_ZONE_ID=$(aws route53 list-hosted-zones-by-name --dns-name "$DOMAIN_PARENT" --query "HostedZones[0].Id" --output text | sed 's/\/hostedzone\///')
if [[ -n "${PARENT_ZONE_ID:-}" ]]; then
    # Check if the delegation record already exists in the parent zone. If it does, skip creating the delegation stack.
    DELEGATION_RECORD_NAME="$TENANT_DOMAIN"
    DELEGATION_RECORD_EXISTS=$(aws route53 list-resource-record-sets --hosted-zone-id "$PARENT_ZONE_ID" --query "ResourceRecordSets[?Name=='$DELEGATION_RECORD_NAME.'].Name" --output text)
    if [[ -n "$DELEGATION_RECORD_EXISTS" ]]; then
        echo "Delegation record $DELEGATION_RECORD_NAME already exists in parent zone $DOMAIN_PARENT; skipping delegation stack deployment"
    else
        R53_DELEGATION_STACK_NAME="$TENANT_ID-r53-zone-delegation-stack"
        echo "Deploying parent-zone delegation stack $R53_DELEGATION_STACK_NAME with PARENT_ZONE_ID=$PARENT_ZONE_ID"
        deploy_stack_safe "$R53_DELEGATION_STACK_NAME" \
            --template-file c3-cform/tenant/r53-zone-delegation.cform.yaml \
            --parameter-overrides \
                ParentZoneId="$PARENT_ZONE_ID" \
                DelegatedSubdomain="$TENANT_DOMAIN" \
                TenantId="$TENANT_ID"
    fi
else
    echo "PARENT_ZONE_ID not set; skipping parent-zone delegation stack"
fi

CERT_STACK_NAME="$TENANT_ID-acm-cert-stack"
echo "Deploying ACM certificate stack $CERT_STACK_NAME"
deploy_stack_safe "$CERT_STACK_NAME" \
    --template-file c3-cform/tenant/acm-cert.cform.yaml \
    --parameter-overrides \
        TenantId="$TENANT_ID" \
        DomainName="$TENANT_DOMAIN" \
        HostedZoneId="$TENANT_ZONE_ID"

REPOSITORY_NAME="c3-ubi"
echo "Deploying ECR repository stack $TENANT_ID-ecr-$REPOSITORY_NAME"
deploy_stack_safe "$TENANT_ID-ecr-$REPOSITORY_NAME" \
    --template-file c3-cform/tenant/ecr-repository.cform.yaml \
    --parameter-overrides RepositoryName="$REPOSITORY_NAME" ScanOnPush="$ECR_SCAN_ON_PUSH"

REPOSITORY_NAME="c3-api"
echo "Deploying ECR repository stack $TENANT_ID-ecr-$REPOSITORY_NAME"
deploy_stack_safe "$TENANT_ID-ecr-$REPOSITORY_NAME" \
    --template-file c3-cform/tenant/ecr-repository.cform.yaml \
    --parameter-overrides RepositoryName="$REPOSITORY_NAME" ScanOnPush="$ECR_SCAN_ON_PUSH"

if [[ "$ECR_SIGNING_ENABLED" == "true" ]]; then
    echo "Deploying shared ECR signing profile stack $ECR_SIGNING_STACK_NAME"
    echo "Using ECR signing profile name: $ECR_SIGNING_PROFILE_NAME"
    deploy_stack_safe "$ECR_SIGNING_STACK_NAME" \
        --template-file c3-cform/tenant/ecr-signing.cform.yaml \
        --parameter-overrides \
            ProfileName="$ECR_SIGNING_PROFILE_NAME"
fi

VPC_STACK_NAME="$TENANT_ID-vpc-3ha-stack"
echo "Deploying VPC stack $VPC_STACK_NAME"
deploy_stack_safe "$VPC_STACK_NAME" \
    --template-file c3-cform/tenant/vpc-3ha.cform.yaml \
    --parameter-overrides TenantId="$TENANT_ID"

EB_STACK_NAME="$TENANT_ID-eb-application-stack"
EB_APPLICATION_NAME="$TENANT_ID-api-app"
echo "Deploying Elastic Beanstalk application stack $EB_STACK_NAME"
deploy_stack_safe "$EB_STACK_NAME" \
    --template-file c3-cform/tenant/eb-application.yaml \
    --parameter-overrides \
        ApplicationName="$EB_APPLICATION_NAME"

##
popd
echo "Script[$0] completed"
