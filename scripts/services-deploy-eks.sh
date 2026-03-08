#!/usr/bin/env bash
set -euo pipefail

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
pushd "$DIR/.." >/dev/null

echo "Script [$0] started"

TENANT_ID=${TENANT_ID:-"c3"}
ENV_ID=${ENV_ID:-"local"}
STACK_PREFIX="${TENANT_ID}-${ENV_ID}"
AWS_REGION=${AWS_REGION:-$(aws configure get region)}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}

C3_API_REPOSITORY_URI=${C3_API_REPOSITORY_URI:-"${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/c3-api"}
C3_API_IMAGE_VERSION=${C3_API_IMAGE_VERSION:-"$(cat version.x.txt).$(cat version.y.txt).$(cat version.z.txt)"}
C3_API_IMAGE_URI=${C3_API_IMAGE_URI:-"$C3_API_REPOSITORY_URI:$C3_API_IMAGE_VERSION"}

KAPI_STACK_NAME="$STACK_PREFIX-kapi-stack"
KAPI_SERVICE_NAME=${KAPI_SERVICE_NAME:-"kapi"}
KAPI_NAMESPACE=${KAPI_NAMESPACE:-"default"}
KAPI_CONTAINER_PORT=${KAPI_CONTAINER_PORT:-"10274"}
KAPI_REPLICAS=${KAPI_REPLICAS:-"1"}
KAPI_PATH_PATTERNS=${KAPI_PATH_PATTERNS:-"/kapi,/kapi/*"}
KAPI_HEALTH_CHECK_PATH=${KAPI_HEALTH_CHECK_PATH:-"/kapi/"}
KAPI_LISTENER_RULE_PRIORITY=${KAPI_LISTENER_RULE_PRIORITY:-"2049"}
KAPI_INDEX_MESSAGE=${KAPI_INDEX_MESSAGE:-"Welcome to C3 KAPI on EKS"}
KAPI_EKS_CLUSTER_NAME=${KAPI_EKS_CLUSTER_NAME:-"${ENV_ID}-eks-cluster"}
KUBECONFIG_PATH=${KUBECONFIG_PATH:-"/tmp/${ENV_ID}-eks-kubeconfig"}

if ! command -v kubectl >/dev/null 2>&1; then
    echo "ERROR: kubectl is required to deploy kapi on EKS"
    exit 1
fi

echo "Deploying kapi workload to EKS cluster: $KAPI_EKS_CLUSTER_NAME"
AWS_PAGER="" aws eks update-kubeconfig --name "$KAPI_EKS_CLUSTER_NAME" --region "$AWS_REGION" --kubeconfig "$KUBECONFIG_PATH" >/dev/null
export KUBECONFIG="$KUBECONFIG_PATH"

kubectl -n "$KAPI_NAMESPACE" create deployment "$KAPI_SERVICE_NAME" \
    --image="$C3_API_IMAGE_URI" \
    --replicas="$KAPI_REPLICAS" \
    --port="$KAPI_CONTAINER_PORT" \
    --dry-run=client -o yaml | kubectl apply -f -

kubectl -n "$KAPI_NAMESPACE" set env deployment/"$KAPI_SERVICE_NAME" \
    C3_INDEX_MESSAGE="$KAPI_INDEX_MESSAGE"

kubectl -n "$KAPI_NAMESPACE" create service clusterip "$KAPI_SERVICE_NAME" \
    --tcp="$KAPI_CONTAINER_PORT:$KAPI_CONTAINER_PORT" \
    --dry-run=client -o yaml | kubectl apply -f -

kubectl -n "$KAPI_NAMESPACE" rollout status deployment/"$KAPI_SERVICE_NAME" --timeout=300s

echo "Deploying kapi ALB routing stack: $KAPI_STACK_NAME"
aws cloudformation deploy \
    --stack-name "$KAPI_STACK_NAME" \
    --template-file c3-cform/service/kapi-eks-alb-service.cform.yaml \
    --parameter-overrides \
        TenantId="$TENANT_ID" \
        EnvId="$ENV_ID" \
        ServiceName="$KAPI_SERVICE_NAME" \
        ContainerPort="$KAPI_CONTAINER_PORT" \
        PathPatterns="$KAPI_PATH_PATTERNS" \
        HealthCheckPath="$KAPI_HEALTH_CHECK_PATH" \
        ListenerRulePriority="$KAPI_LISTENER_RULE_PRIORITY"

KAPI_TARGET_GROUP_ARN=$(aws cloudformation describe-stacks \
    --stack-name "$KAPI_STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='KapiTargetGroupArn'].OutputValue|[0]" \
    --output text)

if [[ -z "$KAPI_TARGET_GROUP_ARN" || "$KAPI_TARGET_GROUP_ARN" == "None" ]]; then
    echo "ERROR: Unable to resolve KapiTargetGroupArn from stack $KAPI_STACK_NAME"
    exit 1
fi

POD_IPS=$(kubectl -n "$KAPI_NAMESPACE" get pods -l app="$KAPI_SERVICE_NAME" -o jsonpath='{range .items[*]}{.status.podIP}{" "}{end}')
if [[ -z "$POD_IPS" ]]; then
    echo "ERROR: No pod IPs found for label app=$KAPI_SERVICE_NAME in namespace $KAPI_NAMESPACE"
    exit 1
fi

EXISTING_TARGETS=$(aws elbv2 describe-target-health \
    --target-group-arn "$KAPI_TARGET_GROUP_ARN" \
    --query 'TargetHealthDescriptions[].Target.Id' \
    --output text 2>/dev/null || true)

for existing_target in $EXISTING_TARGETS; do
    aws elbv2 deregister-targets \
        --target-group-arn "$KAPI_TARGET_GROUP_ARN" \
        --targets "Id=$existing_target,Port=$KAPI_CONTAINER_PORT" >/dev/null || true
done

for pod_ip in $POD_IPS; do
    echo "Registering kapi pod target: $pod_ip:$KAPI_CONTAINER_PORT"
    aws elbv2 register-targets \
        --target-group-arn "$KAPI_TARGET_GROUP_ARN" \
        --targets "Id=$pod_ip,Port=$KAPI_CONTAINER_PORT"
done

echo "kapi target health status:"
aws elbv2 describe-target-health --target-group-arn "$KAPI_TARGET_GROUP_ARN"

popd >/dev/null
echo "Script [$0] completed"
