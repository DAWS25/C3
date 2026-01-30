#!/usr/bin/env bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
pushd "$DIR/.."
#!

source $DIR/env-build.sh

aws sts get-caller-identity

ENV_ID=${ENV_ID:-"project-alpha"}

pushd c3-cform

echo "## Deploying WEB stack..."

BUCKET_STACK_NAME="$ENV_ID-web-bucket-stack"
aws cloudformation deploy \
    --stack-name "$BUCKET_STACK_NAME" \
    --template-file web-bucket.cform.yaml \
    --parameter-overrides EnvId="$ENV_ID"

BUCKET_NAME=$(aws cloudformation describe-stacks \
    --stack-name "$BUCKET_STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='ResourcesBucketName'].OutputValue" \
    --output text)    

WEB_BUILD_DIR="../c3-web/build/"
aws s3 sync $WEB_BUILD_DIR s3://$BUCKET_NAME/ --delete

# API_STACK_NAME="$ENV_ID-api-stack"
# echo "## deploying API stack [$API_STACK_NAME]"
# sam deploy  -t "api-sam.cform.yaml"  \
#     --resolve-s3 \
#     --stack-name "$API_STACK_NAME" \
#     --capabilities CAPABILITY_NAMED_IAM 

echo "## deploying DISTRIBUTION stack..."
aws cloudformation deploy \
    --stack-name $ENV_ID-web-distribution-stack \
    --template-file web-distribution.cform.yaml \
    --parameter-overrides \
        EnvId="$ENV_ID" \
        DomainName="$DOMAIN_NAME" \
        HostedZoneId="$ZONE_ID" \
        CertificateArn="$CERTIFICATE_ARN"


popd

#!
popd
