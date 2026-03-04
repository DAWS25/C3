#!/usr/bin/env bash
set -euo pipefail
DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
pushd "$DIR/.."
echo "Script[$0] started"
##

TENANT_ID=${TENANT_ID:-"c3"}
DOMAIN_PARENT=${DOMAIN_PARENT:-"daws25.com"}
DOMAIN_NAME=${DOMAIN_NAME:-"$TENANT_ID.$DOMAIN_PARENT"}

if [[ -z "$DOMAIN_NAME" ]]; then
    echo "DOMAIN_NAME is required"
    exit 1
fi

R53_STACK_NAME="$TENANT_ID-r53-zone-stack"
aws cloudformation deploy --stack-name "$R53_STACK_NAME" \
    --template-file c3-cform/tenant/r53-zone.cform.yaml \
    --parameter-overrides TenantId="$TENANT_ID" DomainName="$DOMAIN_NAME"

# Lookup PARENT_ZONE_ID by searching route53 zones for one that matches the DOMAIN_PARENT. This is used to create a delegation from the parent domain name.
PARENT_ZONE_ID=$(aws route53 list-hosted-zones-by-name --dns-name "$DOMAIN_PARENT" --query "HostedZones[0].Id" --output text | sed 's/\/hostedzone\///')
if [[ -n "${PARENT_ZONE_ID:-}" ]]; then
    R53_DELEGATION_STACK_NAME="$TENANT_ID-r53-zone-delegation-stack"
    echo "Deploying parent-zone delegation stack $R53_DELEGATION_STACK_NAME with PARENT_ZONE_ID=$PARENT_ZONE_ID"
    aws cloudformation deploy --stack-name "$R53_DELEGATION_STACK_NAME" \
        --template-file c3-cform/tenant/r53-zone-delegation.cform.yaml \
        --parameter-overrides \
            ParentZoneId="$PARENT_ZONE_ID" \
            DelegatedSubdomain="$DOMAIN_NAME" \
            TenantId="$TENANT_ID"
else
    echo "PARENT_ZONE_ID not set; skipping parent-zone delegation stack"
fi

REPOSITORY_NAME="c3-ubi"
aws cloudformation deploy --stack-name "$TENANT_ID-ecr-$REPOSITORY_NAME" \
    --template-file c3-cform/tenant/ecr-repository.cform.yaml \
    --parameter-overrides RepositoryName="$REPOSITORY_NAME"

REPOSITORY_NAME="c3-api"
aws cloudformation deploy --stack-name "$TENANT_ID-ecr-$REPOSITORY_NAME" \
    --template-file c3-cform/tenant/ecr-repository.cform.yaml \
    --parameter-overrides RepositoryName="$REPOSITORY_NAME"

VPC_STACK_NAME="$TENANT_ID-vpc-3ha-stack"
aws cloudformation deploy --stack-name "$VPC_STACK_NAME" \
    --template-file c3-cform/tenant/vpc-3ha.cform.yaml \
    --parameter-overrides TenantId="$TENANT_ID"

##
popd
echo "Script[$0] completed"
