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
DOMAIN_NAME=${DOMAIN_NAME:-"$ENV_DOMAIN"}
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
echo "## Deploying DISTRIBUTION stack..."
aws cloudformation deploy \
    --stack-name "$DISTRIBUTION_STACK_NAME" \
    --template-file c3-cform/distribution/web-distribution.cform.yaml \
    --parameter-overrides \
        EnvId="$ENV_ID" \
        TenantId="$TENANT_ID" \
        DomainName="$DOMAIN_NAME" \
        HostedZoneId="$HOSTED_ZONE_ID" \
        CertificateArn="$CERTIFICATE_ARN"

echo "Script [$0] completed for ENV_ID=$ENV_ID and DOMAIN_NAME=$DOMAIN_NAME"
#!
popd
