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

C3_KAPI_REPOSITORY_URI=${C3_KAPI_REPOSITORY_URI:-"${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/c3-api"}
C3_KAPI_IMAGE_VERSION=${C3_KAPI_IMAGE_VERSION:-"$(cat version.x.txt).$(cat version.y.txt).$(cat version.z.txt)"}
C3_KAPI_IMAGE_URI=${C3_KAPI_IMAGE_URI:-"$C3_KAPI_REPOSITORY_URI:$C3_KAPI_IMAGE_VERSION"}
C3_VERSION=${C3_VERSION:-"$C3_KAPI_IMAGE_VERSION"}

C3_KAPI_STACK_NAME="$STACK_PREFIX-kapi-stack"
C3_KAPI_SERVICE_NAME=${C3_KAPI_SERVICE_NAME:-"kapi"}
C3_KAPI_NAMESPACE=${C3_KAPI_NAMESPACE:-"default"}
C3_KAPI_CONTAINER_PORT=${C3_KAPI_CONTAINER_PORT:-"15274"}
C3_KAPI_REPLICAS=${C3_KAPI_REPLICAS:-"1"}
C3_KAPI_PATH_PATTERNS=${C3_KAPI_PATH_PATTERNS:-"/kapi,/kapi/*"}
C3_KAPI_HEALTH_CHECK_PATH=${C3_KAPI_HEALTH_CHECK_PATH:-"/kapi/"}
C3_KAPI_LISTENER_RULE_PRIORITY=${C3_KAPI_LISTENER_RULE_PRIORITY:-"15274"}
C3_KAPI_EKS_CLUSTER_NAME=${C3_KAPI_EKS_CLUSTER_NAME:-"${ENV_ID}-eks-cluster"}
KUBECONFIG_PATH=${KUBECONFIG_PATH:-"/tmp/${ENV_ID}-eks-kubeconfig"}

if ! command -v kubectl >/dev/null 2>&1; then
    echo "ERROR: kubectl is required to deploy kapi on EKS"
    exit 1
fi

echo "Deploying kapi workload to EKS cluster: $C3_KAPI_EKS_CLUSTER_NAME"
AWS_PAGER="" aws eks update-kubeconfig --name "$C3_KAPI_EKS_CLUSTER_NAME" --region "$AWS_REGION" --kubeconfig "$KUBECONFIG_PATH" >/dev/null
export KUBECONFIG="$KUBECONFIG_PATH"

echo "Ensuring EKS Fargate logging config exists"
kubectl get namespace aws-observability >/dev/null 2>&1 || kubectl create namespace aws-observability
kubectl label namespace aws-observability aws-observability=enabled --overwrite >/dev/null
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
    name: aws-logging
    namespace: aws-observability
data:
    output.conf: |
        [OUTPUT]
                Name cloudwatch_logs
                Match *
                region ${AWS_REGION}
                log_group_name /aws/eks/${C3_KAPI_EKS_CLUSTER_NAME}/fargate
                log_stream_prefix fluent-bit-
                auto_create_group true
EOF

kubectl -n "$C3_KAPI_NAMESPACE" create deployment "$C3_KAPI_SERVICE_NAME" \
    --image="$C3_KAPI_IMAGE_URI" \
    --replicas="$C3_KAPI_REPLICAS" \
    --port="$C3_KAPI_CONTAINER_PORT" \
    --dry-run=client -o yaml | kubectl apply -f -

kubectl -n "$C3_KAPI_NAMESPACE" set env deployment/"$C3_KAPI_SERVICE_NAME" \
    C3_VERSION="$C3_VERSION" \
    QUARKUS_PROFILE="eks"

kubectl -n "$C3_KAPI_NAMESPACE" create service clusterip "$C3_KAPI_SERVICE_NAME" \
    --tcp="$C3_KAPI_CONTAINER_PORT:$C3_KAPI_CONTAINER_PORT" \
    --dry-run=client -o yaml | kubectl apply -f -

kubectl -n "$C3_KAPI_NAMESPACE" rollout status deployment/"$C3_KAPI_SERVICE_NAME" --timeout=300s

echo "Deploying KAPI stack: $C3_KAPI_STACK_NAME"
aws cloudformation deploy \
    --stack-name "$C3_KAPI_STACK_NAME" \
    --template-file c3-cform/service/api-eks-service.cform.yaml \
    --parameter-overrides \
        TenantId="$TENANT_ID" \
        EnvId="$ENV_ID" \
        ServiceName="$C3_KAPI_SERVICE_NAME" \
        ContainerPort="$C3_KAPI_CONTAINER_PORT" \
        PathPatterns="$C3_KAPI_PATH_PATTERNS" \
        HealthCheckPath="$C3_KAPI_HEALTH_CHECK_PATH" \
        ListenerRulePriority="$C3_KAPI_LISTENER_RULE_PRIORITY"

C3_KAPI_TARGET_GROUP_ARN=$(aws cloudformation describe-stacks \
    --stack-name "$C3_KAPI_STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='KapiTargetGroupArn'].OutputValue|[0]" \
    --output text)

if [[ -z "$C3_KAPI_TARGET_GROUP_ARN" || "$C3_KAPI_TARGET_GROUP_ARN" == "None" ]]; then
    echo "ERROR: Unable to resolve KapiTargetGroupArn from stack $C3_KAPI_STACK_NAME"
    exit 1
fi

POD_IPS=$(kubectl -n "$C3_KAPI_NAMESPACE" get pods -l app="$C3_KAPI_SERVICE_NAME" -o jsonpath='{range .items[*]}{.status.podIP}{" "}{end}')
if [[ -z "$POD_IPS" ]]; then
    echo "ERROR: No pod IPs found for label app=$C3_KAPI_SERVICE_NAME in namespace $C3_KAPI_NAMESPACE"
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

for pod_ip in $POD_IPS; do
    POD_ENI_ID=$(aws ec2 describe-network-interfaces \
        --region "$AWS_REGION" \
        --filters "Name=addresses.private-ip-address,Values=$pod_ip" \
        --query 'NetworkInterfaces[0].NetworkInterfaceId' \
        --output text)

    if [[ -z "$POD_ENI_ID" || "$POD_ENI_ID" == "None" ]]; then
        echo "WARN: Unable to resolve ENI for pod IP $pod_ip"
        continue
    fi

    POD_SECURITY_GROUPS=$(aws ec2 describe-network-interfaces \
        --region "$AWS_REGION" \
        --network-interface-ids "$POD_ENI_ID" \
        --query 'NetworkInterfaces[0].Groups[].GroupId' \
        --output text)

    for pod_sg in $POD_SECURITY_GROUPS; do
        echo "Ensuring ingress on $pod_sg from ALB SG $ALB_SECURITY_GROUP_ID for tcp/$C3_KAPI_CONTAINER_PORT"
        aws ec2 authorize-security-group-ingress \
            --region "$AWS_REGION" \
            --group-id "$pod_sg" \
            --ip-permissions "IpProtocol=tcp,FromPort=$C3_KAPI_CONTAINER_PORT,ToPort=$C3_KAPI_CONTAINER_PORT,UserIdGroupPairs=[{GroupId=$ALB_SECURITY_GROUP_ID}]" \
            >/dev/null 2>&1 || true

        echo "Ensuring temporary public ingress on $pod_sg for tcp/$C3_KAPI_CONTAINER_PORT"
        aws ec2 authorize-security-group-ingress \
            --region "$AWS_REGION" \
            --group-id "$pod_sg" \
            --protocol tcp \
            --port "$C3_KAPI_CONTAINER_PORT" \
            --cidr 0.0.0.0/0 \
            >/dev/null 2>&1 || true
    done
done

EXISTING_TARGETS=$(aws elbv2 describe-target-health \
    --target-group-arn "$C3_KAPI_TARGET_GROUP_ARN" \
    --query 'TargetHealthDescriptions[].Target.Id' \
    --output text 2>/dev/null || true)

for existing_target in $EXISTING_TARGETS; do
    aws elbv2 deregister-targets \
        --target-group-arn "$C3_KAPI_TARGET_GROUP_ARN" \
        --targets "Id=$existing_target,Port=$C3_KAPI_CONTAINER_PORT" >/dev/null || true
done

for pod_ip in $POD_IPS; do
    echo "Registering kapi pod target: $pod_ip:$C3_KAPI_CONTAINER_PORT"
    aws elbv2 register-targets \
        --target-group-arn "$C3_KAPI_TARGET_GROUP_ARN" \
        --targets "Id=$pod_ip,Port=$C3_KAPI_CONTAINER_PORT"
done

echo "kapi target health status:"
aws elbv2 describe-target-health --target-group-arn "$C3_KAPI_TARGET_GROUP_ARN"

popd >/dev/null
echo "Script [$0] completed"
