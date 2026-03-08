# EKS Deployment Fixes

## Issues Identified and Fixed

### 1. VPC Endpoints for ECR Access
**Problem:** Fargate pods in isolated subnets couldn't pull container images from ECR because they had no internet access and no VPC endpoints.

**Solution:** Added VPC endpoints to `c3-cform/env/eks-cluster.cform.yaml`:
- `ECRApiVpcEndpoint` - For ECR API calls
- `ECRDkrVpcEndpoint` - For Docker image pulls
- `S3VpcEndpoint` - For ECR layer storage (Gateway endpoint)

### 2. Security Group Rules for VPC Endpoints
**Problem:** Fargate pods couldn't reach VPC endpoints due to missing security group rules.

**Solution:** Added HTTPS (443) ingress rule to `EKSClusterSecurityGroup` in `c3-cform/env/eks-cluster.cform.yaml`:
```yaml
- IpProtocol: tcp
  FromPort: 443
  ToPort: 443
  SourceSecurityGroupId: !Ref EKSClusterSecurityGroup
  Description: Allow HTTPS for VPC endpoints
```

This allows pods to communicate with VPC endpoints using the same security group.

### 3. Application Root Path
**Problem:** The application was built with root path commented out, causing it to serve at `/` instead of `/kapi/` as required by the ALB routing.

**Solution:** Uncommented and set `quarkus.http.root-path=/kapi` in `c3-api/src/main/resources/application.properties`.

**Note:** This is a build-time property in Quarkus, so the image must be rebuilt after this change.

## Deployment Order

1. Deploy VPC stack (includes route table for S3 endpoint)
2. Deploy EKS cluster stack (includes VPC endpoints and security groups)
3. Build and push container images with correct root path
4. Deploy EKS service using `scripts/services-deploy-eks.sh`

## Verification Steps

After deployment:
1. Check pods are running: `kubectl get pods -n default`
2. Test pod directly: `kubectl exec -n default <pod-name> -- curl -s http://localhost:10274/kapi/`
3. Check ALB target health: `aws elbv2 describe-target-health --target-group-arn <arn>`
4. Test endpoint: `curl https://local.c3.daws25.com/kapi/`

## Files Modified

1. `c3-cform/env/eks-cluster.cform.yaml` - Added VPC endpoints and security group rules
2. `c3-api/src/main/resources/application.properties` - Set root path to /kapi
