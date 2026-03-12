#!/usr/bin/env bash
set -euo pipefail
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$DIR/utils_aws.sh"
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
DOMAIN_NAME=${DOMAIN_NAME:-"$ENV_DOMAIN"}
API_DOMAIN_NAME=${API_DOMAIN_NAME:-"${ENV_ID}-api.${TENANT_DOMAIN}"}
HOSTED_ZONE_ID=${HOSTED_ZONE_ID:-${ZONE_ID:-""}}

delete_stack_if_stale() {
    local stack_name="$1"
    local status
    status=$(stack_status "$stack_name")
    if [[ "$status" == "ROLLBACK_COMPLETE" || "$status" == "REVIEW_IN_PROGRESS" ]]; then
        echo "Deleting stale stack [$status]: $stack_name"
        aws cloudformation delete-stack --stack-name "$stack_name"
        aws cloudformation wait stack-delete-complete --stack-name "$stack_name"
    fi
}

print_failed_changeset_reason() {
    local stack_name="$1"
    local failed_change_set
    local reason

    failed_change_set=$(aws cloudformation list-change-sets \
        --stack-name "$stack_name" \
        --query "reverse(sort_by(Summaries[?Status=='FAILED'], &CreationTime))[0].ChangeSetName" \
        --output text 2>/dev/null || true)

    if [[ -z "$failed_change_set" || "$failed_change_set" == "None" ]]; then
        echo "No failed change set found for stack: $stack_name"
        return
    fi

    reason=$(aws cloudformation describe-change-set \
        --stack-name "$stack_name" \
        --change-set-name "$failed_change_set" \
        --query "StatusReason" \
        --output text 2>/dev/null || true)

    echo "Failed change set: $failed_change_set"
    echo "Validation message: ${reason:-Unavailable}"
}

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

CERT_STACK_NAME="$TENANT_ID-acm-cert-stack"
CERTIFICATE_ARN=${CERTIFICATE_ARN:-$(aws cloudformation describe-stacks \
    --stack-name "$CERT_STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='CertificateArn'].OutputValue" \
    --output text)}

if [[ -z "$CERTIFICATE_ARN" || "$CERTIFICATE_ARN" == "None" ]]; then
  echo "Unable to resolve CertificateArn from stack $CERT_STACK_NAME"
  exit 1
fi

DISTRIBUTION_STACK_NAME="$STACK_PREFIX-web-distribution-stack"
DISTRIBUTION_DNS_ALIAS_STACK_NAME="$STACK_PREFIX-web-distribution-dns-stack"
delete_stack_if_stale "$DISTRIBUTION_STACK_NAME"
delete_stack_if_stale "$DISTRIBUTION_DNS_ALIAS_STACK_NAME"
echo "## Deploying DISTRIBUTION stack..."
if ! aws cloudformation deploy \
    --stack-name "$DISTRIBUTION_STACK_NAME" \
    --template-file c3-cform/distribution/web-distribution.cform.yaml \
    --parameter-overrides \
        EnvId="$ENV_ID" \
        TenantId="$TENANT_ID" \
        DomainName="$DOMAIN_NAME" \
        ApiDomainName="$API_DOMAIN_NAME" \
        CertificateArn="$CERTIFICATE_ARN"; then
    echo "Distribution deploy failed for stack: $DISTRIBUTION_STACK_NAME"
    print_failed_changeset_reason "$DISTRIBUTION_STACK_NAME"
    exit 1
fi

echo "## Deploying DISTRIBUTION DNS ALIAS stack..."
if ! aws cloudformation deploy \
    --stack-name "$DISTRIBUTION_DNS_ALIAS_STACK_NAME" \
    --template-file c3-cform/distribution/web-distribution-dns-alias.cform.yaml \
    --parameter-overrides \
        EnvId="$ENV_ID" \
        DomainName="$DOMAIN_NAME" \
        HostedZoneId="$HOSTED_ZONE_ID"; then
    echo "Distribution DNS alias deploy failed for stack: $DISTRIBUTION_DNS_ALIAS_STACK_NAME"
    print_failed_changeset_reason "$DISTRIBUTION_DNS_ALIAS_STACK_NAME"
    exit 1
fi

echo "Script [$0] completed for ENV_ID=$ENV_ID and DOMAIN_NAME=$DOMAIN_NAME"
#!
popd
