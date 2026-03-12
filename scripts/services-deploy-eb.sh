#!/usr/bin/env bash
set -euo pipefail

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$DIR/utils_aws.sh"
pushd "$DIR/.." >/dev/null

echo "Script [$0] started"

TENANT_ID=${TENANT_ID:-"c3"}
ENV_ID=${ENV_ID:-"local"}
STACK_PREFIX="${TENANT_ID}-${ENV_ID}"
AWS_REGION=${AWS_REGION:-$(aws configure get region)}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}

EB_APPLICATION_NAME=${EB_APPLICATION_NAME:-"${TENANT_ID}-api-app"}
EB_ENVIRONMENT_NAME=${EB_ENVIRONMENT_NAME:-"${TENANT_ID}-api-env"}

C3_EBAPI_STACK_NAME=${C3_EBAPI_STACK_NAME:-"${STACK_PREFIX}-ebapi-stack"}
C3_EBAPI_SERVICE_NAME=${C3_EBAPI_SERVICE_NAME:-"ebapi"}
C3_EBAPI_APP_PORT=${C3_EBAPI_APP_PORT:-"10274"}
C3_EBAPI_TARGET_PORT=${C3_EBAPI_TARGET_PORT:-"80"}
C3_EBAPI_PATH_PATTERNS=${C3_EBAPI_PATH_PATTERNS:-"/ebapi,/ebapi/*"}
C3_EBAPI_HEALTH_CHECK_PATH=${C3_EBAPI_HEALTH_CHECK_PATH:-"/ebapi/"}
C3_EBAPI_LISTENER_RULE_PRIORITY=${C3_EBAPI_LISTENER_RULE_PRIORITY:-"11274"}

C3_API_REPOSITORY_URI=${C3_API_REPOSITORY_URI:-"${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/c3-api"}
C3_API_IMAGE_VERSION=${C3_API_IMAGE_VERSION:-"$(cat version.x.txt).$(cat version.y.txt).$(cat version.z.txt)"}
C3_API_IMAGE_URI=${C3_API_IMAGE_URI:-"$C3_API_REPOSITORY_URI:$C3_API_IMAGE_VERSION"}
C3_VERSION=${C3_VERSION:-"$C3_API_IMAGE_VERSION"}

if [[ -z "$AWS_REGION" || "$AWS_REGION" == "None" ]]; then
    echo "AWS region is not configured. Set AWS_REGION or run aws configure."
    exit 1
fi

echo "Verifying image exists: $C3_API_IMAGE_URI"
aws ecr describe-images \
    --registry-id "$AWS_ACCOUNT_ID" \
    --region "$AWS_REGION" \
    --repository-name "c3-api" \
    --image-ids "imageTag=${C3_API_IMAGE_URI##*:}" >/dev/null

ensure_eb_instance_profile() {
    local profile_name="aws-elasticbeanstalk-ec2-role"
    if aws iam get-instance-profile --instance-profile-name "$profile_name" >/dev/null 2>&1; then
        echo "EB instance profile $profile_name already exists"
        return
    fi
    echo "Creating EB IAM role and instance profile: $profile_name"
    aws iam create-role --role-name "$profile_name" \
        --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]}' >/dev/null
    aws iam attach-role-policy --role-name "$profile_name" \
        --policy-arn arn:aws:iam::aws:policy/AWSElasticBeanstalkWebTier
    aws iam attach-role-policy --role-name "$profile_name" \
        --policy-arn arn:aws:iam::aws:policy/AWSElasticBeanstalkWorkerTier
        aws iam attach-role-policy --role-name "$profile_name" \
            --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly
    aws iam create-instance-profile --instance-profile-name "$profile_name" >/dev/null
    aws iam add-role-to-instance-profile --instance-profile-name "$profile_name" --role-name "$profile_name"
}

echo "Verifying Elastic Beanstalk application: $EB_APPLICATION_NAME"
app_exists=$(aws elasticbeanstalk describe-applications \
    --application-names "$EB_APPLICATION_NAME" \
    --query 'Applications[0].ApplicationName' --output text 2>/dev/null || true)
if [[ -z "$app_exists" || "$app_exists" == "None" ]]; then
    echo "EB application missing; deploying tenant stack to create it"
    EB_APPLICATION_STACK_NAME="${TENANT_ID}-eb-application-stack"
    deploy_stack_safe "$EB_APPLICATION_STACK_NAME" \
        --template-file c3-cform/tenant/eb-application.yaml \
        --parameter-overrides ApplicationName="$EB_APPLICATION_NAME"
fi

echo "Verifying Elastic Beanstalk environment: $EB_ENVIRONMENT_NAME"
environment_status=$(aws elasticbeanstalk describe-environments \
    --application-name "$EB_APPLICATION_NAME" \
    --environment-names "$EB_ENVIRONMENT_NAME" \
    --query 'Environments[0].Status' \
    --output text 2>/dev/null || true)

if [[ -z "$environment_status" || "$environment_status" == "None" || "$environment_status" == "Terminated" ]]; then
    echo "Waiting for any Terminating environments to complete..."
    for i in {1..20}; do
        environment_status=$(aws elasticbeanstalk describe-environments \
            --application-name "$EB_APPLICATION_NAME" \
            --environment-names "$EB_ENVIRONMENT_NAME" \
            --query 'Environments[0].Status' --output text 2>/dev/null || true)
        [[ "$environment_status" == "Terminating" ]] || break
        echo "  [$i/20] EB environment still Terminating..."
        sleep 30
    done

    echo "Creating EB environment $EB_ENVIRONMENT_NAME in application $EB_APPLICATION_NAME (was: ${environment_status:-none})..."
    ensure_eb_instance_profile

    EB_VPC_ID=$(aws cloudformation list-exports \
        --query "Exports[?Name=='${TENANT_ID}-VpcId'].Value|[0]" --output text)
    EB_SUBNET_IDS=$(aws cloudformation list-exports \
        --query "Exports[?Name=='${TENANT_ID}-PublicSubnetIds'].Value|[0]" --output text)
    echo "  Using VPC: $EB_VPC_ID, Subnets: $EB_SUBNET_IDS"

    aws elasticbeanstalk create-environment \
        --application-name "$EB_APPLICATION_NAME" \
        --environment-name "$EB_ENVIRONMENT_NAME" \
        --solution-stack-name "64bit Amazon Linux 2023 v4.11.0 running Docker" \
        --option-settings "[
            {\"Namespace\":\"aws:autoscaling:launchconfiguration\",\"OptionName\":\"InstanceType\",\"Value\":\"t3.micro\"},
            {\"Namespace\":\"aws:autoscaling:launchconfiguration\",\"OptionName\":\"IamInstanceProfile\",\"Value\":\"aws-elasticbeanstalk-ec2-role\"},
            {\"Namespace\":\"aws:autoscaling:asg\",\"OptionName\":\"MinSize\",\"Value\":\"1\"},
            {\"Namespace\":\"aws:autoscaling:asg\",\"OptionName\":\"MaxSize\",\"Value\":\"4\"},
            {\"Namespace\":\"aws:elasticbeanstalk:environment\",\"OptionName\":\"ServiceRole\",\"Value\":\"aws-elasticbeanstalk-service-role\"},
            {\"Namespace\":\"aws:ec2:vpc\",\"OptionName\":\"VPCId\",\"Value\":\"$EB_VPC_ID\"},
            {\"Namespace\":\"aws:ec2:vpc\",\"OptionName\":\"Subnets\",\"Value\":\"$EB_SUBNET_IDS\"},
            {\"Namespace\":\"aws:ec2:vpc\",\"OptionName\":\"AssociatePublicIpAddress\",\"Value\":\"true\"}
        ]" >/dev/null

    echo "Waiting for EB environment to become Ready (this may take several minutes)..."
    for i in {1..30}; do
        environment_status=$(aws elasticbeanstalk describe-environments \
            --application-name "$EB_APPLICATION_NAME" \
            --environment-names "$EB_ENVIRONMENT_NAME" \
            --query 'Environments[0].Status' --output text 2>/dev/null || true)
        echo "  [$i/30] EB environment status: $environment_status"
        [[ "$environment_status" == "Ready" ]] && break
        [[ "$environment_status" == "Terminated" ]] && { echo "ERROR: EB environment terminated"; exit 1; }
        sleep 30
    done
    if [[ "$environment_status" != "Ready" ]]; then
        echo "ERROR: EB environment $EB_ENVIRONMENT_NAME did not reach Ready within timeout"
        exit 1
    fi
fi

VERSION_LABEL="ebapi-${C3_API_IMAGE_VERSION//./-}-$(date +%Y%m%d%H%M%S)"
S3_BUCKET=$(aws elasticbeanstalk create-storage-location --query S3Bucket --output text)
S3_KEY="ebapi/${TENANT_ID}/${ENV_ID}/${VERSION_LABEL}.zip"

tmp_dir=$(mktemp -d)
cat >"${tmp_dir}/Dockerrun.aws.json" <<EOF
{
  "AWSEBDockerrunVersion": "1",
  "Image": {
    "Name": "${C3_API_IMAGE_URI}",
    "Update": "true"
  },
  "Ports": [
    {
            "ContainerPort": "${C3_EBAPI_APP_PORT}"
    }
  ]
}
EOF

(cd "$tmp_dir" && zip -q app.zip Dockerrun.aws.json)
aws s3 cp "${tmp_dir}/app.zip" "s3://${S3_BUCKET}/${S3_KEY}" >/dev/null
rm -rf "$tmp_dir"

echo "Creating EB application version: $VERSION_LABEL"
aws elasticbeanstalk create-application-version \
    --application-name "$EB_APPLICATION_NAME" \
    --version-label "$VERSION_LABEL" \
    --source-bundle S3Bucket="$S3_BUCKET",S3Key="$S3_KEY" >/dev/null

echo "Updating EB environment to version $VERSION_LABEL"
aws elasticbeanstalk update-environment \
    --environment-name "$EB_ENVIRONMENT_NAME" \
    --version-label "$VERSION_LABEL" \
    --option-settings \
      Namespace=aws:elasticbeanstalk:application:environment,OptionName=QUARKUS_PROFILE,Value=eb \
      Namespace=aws:elasticbeanstalk:application:environment,OptionName=C3_VERSION,Value="$C3_VERSION" \
      Namespace=aws:elasticbeanstalk:application:environment,OptionName=C3_INDEX_MESSAGE,Value="Hi from C3 EBAPI on Elastic Beanstalk!" >/dev/null

echo "Waiting for EB environment update to complete..."
for i in {1..60}; do
    env_status=$(aws elasticbeanstalk describe-environments \
        --application-name "$EB_APPLICATION_NAME" \
        --environment-names "$EB_ENVIRONMENT_NAME" \
        --query 'Environments[0].Status' --output text 2>/dev/null || true)
    echo "  [$i/60] EB environment status: $env_status"
    [[ "$env_status" == "Ready" ]] && break
    [[ "$env_status" == "Terminated" ]] && { echo "ERROR: EB environment terminated during update"; exit 1; }
    sleep 30
done
if [[ "$env_status" != "Ready" ]]; then
    echo "ERROR: EB environment $EB_ENVIRONMENT_NAME did not reach Ready after update (status: $env_status)"
    exit 1
fi

echo "Deploying EBAPI service stack: $C3_EBAPI_STACK_NAME"
deploy_stack_safe "$C3_EBAPI_STACK_NAME" \
    --template-file c3-cform/service/api-eb-service.cform.yaml \
    --parameter-overrides \
        TenantId="$TENANT_ID" \
        EnvId="$ENV_ID" \
        ServiceName="$C3_EBAPI_SERVICE_NAME" \
        ContainerPort="$C3_EBAPI_TARGET_PORT" \
        PathPatterns="$C3_EBAPI_PATH_PATTERNS" \
        HealthCheckPath="$C3_EBAPI_HEALTH_CHECK_PATH" \
        ListenerRulePriority="$C3_EBAPI_LISTENER_RULE_PRIORITY"

C3_EBAPI_TARGET_GROUP_ARN=$(aws cloudformation describe-stacks \
    --stack-name "$C3_EBAPI_STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='EbapiTargetGroupArn'].OutputValue|[0]" \
    --output text)

if [[ -z "$C3_EBAPI_TARGET_GROUP_ARN" || "$C3_EBAPI_TARGET_GROUP_ARN" == "None" ]]; then
    echo "ERROR: Unable to resolve EbapiTargetGroupArn from stack $C3_EBAPI_STACK_NAME"
    exit 1
fi

EB_INSTANCE_IDS=$(aws elasticbeanstalk describe-environment-resources \
    --environment-name "$EB_ENVIRONMENT_NAME" \
    --query 'EnvironmentResources.Instances[].Id' \
    --output text)

if [[ -z "$EB_INSTANCE_IDS" || "$EB_INSTANCE_IDS" == "None" ]]; then
    echo "ERROR: No EC2 instances found in EB environment $EB_ENVIRONMENT_NAME"
    exit 1
fi

ALB_SECURITY_GROUP_ID=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_PREFIX-alb-services-stack" \
    --query "Stacks[0].Outputs[?OutputKey=='ALBSecurityGroupId'].OutputValue|[0]" \
    --output text)

if [[ -z "$ALB_SECURITY_GROUP_ID" || "$ALB_SECURITY_GROUP_ID" == "None" ]]; then
    echo "ERROR: Unable to resolve ALBSecurityGroupId from stack $STACK_PREFIX-alb-services-stack"
    exit 1
fi

for instance_id in $EB_INSTANCE_IDS; do
    INSTANCE_SECURITY_GROUPS=$(aws ec2 describe-instances \
        --region "$AWS_REGION" \
        --instance-ids "$instance_id" \
        --query 'Reservations[].Instances[].SecurityGroups[].GroupId' \
        --output text)

    for instance_sg in $INSTANCE_SECURITY_GROUPS; do
        echo "Ensuring ingress on $instance_sg from ALB SG $ALB_SECURITY_GROUP_ID for tcp/$C3_EBAPI_TARGET_PORT"
        aws ec2 authorize-security-group-ingress \
            --region "$AWS_REGION" \
            --group-id "$instance_sg" \
            --ip-permissions "IpProtocol=tcp,FromPort=$C3_EBAPI_TARGET_PORT,ToPort=$C3_EBAPI_TARGET_PORT,UserIdGroupPairs=[{GroupId=$ALB_SECURITY_GROUP_ID}]" \
            >/dev/null 2>&1 || true
    done
done

EXISTING_TARGETS=$(aws elbv2 describe-target-health \
    --target-group-arn "$C3_EBAPI_TARGET_GROUP_ARN" \
    --query 'TargetHealthDescriptions[].Target.Id' \
    --output text 2>/dev/null || true)

for existing_target in $EXISTING_TARGETS; do
    aws elbv2 deregister-targets \
        --target-group-arn "$C3_EBAPI_TARGET_GROUP_ARN" \
        --targets "Id=$existing_target,Port=$C3_EBAPI_TARGET_PORT" >/dev/null || true
done

for instance_id in $EB_INSTANCE_IDS; do
    echo "Registering ebapi instance target: $instance_id:$C3_EBAPI_TARGET_PORT"
    aws elbv2 register-targets \
        --target-group-arn "$C3_EBAPI_TARGET_GROUP_ARN" \
        --targets "Id=$instance_id,Port=$C3_EBAPI_TARGET_PORT"
done

echo "ebapi target health status:"
aws elbv2 describe-target-health --target-group-arn "$C3_EBAPI_TARGET_GROUP_ARN"

popd >/dev/null
echo "Script [$0] completed"
