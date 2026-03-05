#!/bin/bash
set -e
DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
pushd "$DIR/.."
echo "Script[$0] started"
##

DOCKER_CMD=${DOCKER_CMD:-"docker"}
export AWS_PAGER=""

export VERSION_X=$(cat version.x.txt)
export VERSION_Y=$(cat version.y.txt)
echo "$(date +%Y%m%d%H%M%S)" > version.z.txt
export VERSION_Z=$(cat version.z.txt)
export UBI_VERSION="${VERSION_X}.${VERSION_Y}"
export BUILD_VERSION="${UBI_VERSION}.${VERSION_Z}"
echo "Build and push images started for version[$BUILD_VERSION] using command[$DOCKER_CMD]"

SKIP_PRUNE=${SKIP_PRUNE:-"true"}
if [ "$SKIP_PRUNE" == "false" ]; then
    echo "Pruning local docker system"
    $DOCKER_CMD system prune -f
fi

AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION=$(aws configure get region)
echo "Authenticating to ECR Registry for account[$AWS_ACCOUNT_ID] and region[$AWS_REGION]"
aws ecr get-login-password --region $AWS_REGION | $DOCKER_CMD login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

echo "Bulding images"
VERSION_XARGS="--build-arg BUILD_VERSION=${BUILD_VERSION} --build-arg UBI_VERSION=${UBI_VERSION}"
BUILD_XARGS="--no-cache --progress=plain $VERSION_XARGS" # DEBUG ARGUMENTS
# BUILD_XARGS="$VERSION_XARGS" # REGULAR ARGUMENTS

echo "Building C3 UBI image"
C3_UBI_TAG="c3-ubi:$UBI_VERSION"
$DOCKER_CMD build $BUILD_XARGS -f c3-ubi/Containerfile -t $C3_UBI_TAG . 

echo "Building C3 build image"
C3_BUILD_TAG="c3-build:$BUILD_VERSION"
$DOCKER_CMD build $BUILD_XARGS -f c3-build/Containerfile -t $C3_BUILD_TAG .

echo "Building C3 API image"
C3_API_TAG="c3-api:$BUILD_VERSION"
$DOCKER_CMD build $BUILD_XARGS -f c3-api/Containerfile -t $C3_API_TAG .


SKIP_PUSH=${SKIP_PUSH:-"false"}
if [ "$SKIP_PUSH" == "false" ]; then
    echo "Pushing images"
    export REGISTRY_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
    $DOCKER_CMD tag $C3_UBI_TAG $REGISTRY_URI/$C3_UBI_TAG
    $DOCKER_CMD push $REGISTRY_URI/$C3_UBI_TAG
    echo "Pushed image URI: $REGISTRY_URI/$C3_UBI_TAG"
    echo "ECR URL: https://${AWS_REGION}.console.aws.amazon.com/ecr/repositories/private/${AWS_ACCOUNT_ID}/c3-ubi?region=${AWS_REGION}"

    $DOCKER_CMD tag $C3_API_TAG $REGISTRY_URI/$C3_API_TAG
    $DOCKER_CMD push $REGISTRY_URI/$C3_API_TAG
    echo "Pushed image URI: $REGISTRY_URI/$C3_API_TAG"
    echo "ECR URL: https://${AWS_REGION}.console.aws.amazon.com/ecr/repositories/private/${AWS_ACCOUNT_ID}/c3-api?region=${AWS_REGION}"
fi

echo "Push images completed for version $VERSION"
echo "# Check the build image:"
echo "docker run -it --rm $C3_BUILD_TAG bash"

echo "# Run the API image:"
echo "docker run -it --rm -p 10274:10274 $C3_API_TAG"

##
popd
echo "Script[$0] completed"
