#!/bin/bash
set -e
DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
pushd "$DIR/.."
echo "Script[$0] started"
##

# Ensure notation is available in PATH if installed locally
export PATH="${HOME}/.local/bin:${PATH}"

DOCKER_CMD=${DOCKER_CMD:-"docker"}
TENANT_ID=${TENANT_ID:-"c3"}
SIGN_IMAGES=${SIGN_IMAGES:-"true"}
ECR_SIGNING_STACK_NAME=${ECR_SIGNING_STACK_NAME:-"${TENANT_ID}-ecr-signing-stack"}
export AWS_PAGER=""

export VERSION_X=$(cat version.x.txt)
export VERSION_Y=$(cat version.y.txt)
export VERSION_Z=$(date +%H%M%S)
export UBI_VERSION="${VERSION_X}.${VERSION_Y}"
export BUILD_VERSION="${VERSION_X}.${VERSION_Y}.${VERSION_Z}"
echo "Build and push images started for version[$BUILD_VERSION] using command[$DOCKER_CMD]"

SKIP_PRUNE=${SKIP_PRUNE:-"true"}
if [ "$SKIP_PRUNE" == "false" ]; then
    echo "Pruning local docker system"
    $DOCKER_CMD system prune -f
fi

AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION=$(aws configure get region)
REGISTRY_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
echo "Authenticating to ECR Registry for account[$AWS_ACCOUNT_ID] and region[$AWS_REGION]"
aws ecr get-login-password --region $AWS_REGION | $DOCKER_CMD login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

ecr_tag_exists() {
    local repository="$1"
    local tag="$2"
    aws ecr describe-images \
        --repository-name "$repository" \
        --image-ids imageTag="$tag" \
        --region "$AWS_REGION" >/dev/null 2>&1
}

get_signing_profile_arn() {
    aws cloudformation describe-stacks \
    --stack-name "$ECR_SIGNING_STACK_NAME" \
        --query "Stacks[0].Outputs[?OutputKey=='SigningProfileArn'].OutputValue|[0]" \
        --output text 2>/dev/null || true
}

sign_image_if_enabled() {
    local repository="$1"
    local tag="$2"

    if [[ "$SIGN_IMAGES" != "true" ]]; then
        return
    fi

    if ! command -v notation >/dev/null 2>&1; then
        echo "Skipping signing for $repository:$tag (notation CLI not installed)"
        return
    fi

    if ! notation plugin ls 2>/dev/null | grep -q "com.amazonaws.signer.notation.plugin"; then
        echo "Skipping signing for $repository:$tag (AWS Signer notation plugin not installed)"
        return
    fi

    local signing_profile_arn
    signing_profile_arn=$(get_signing_profile_arn)
    if [[ -z "$signing_profile_arn" || "$signing_profile_arn" == "None" ]]; then
        echo "Skipping signing for $repository:$tag (signing profile stack not found)"
        return
    fi

    local image_ref="$REGISTRY_URI/$repository:$tag"
    echo "Signing image: $image_ref"
    notation sign --plugin com.amazonaws.signer.notation.plugin --id "$signing_profile_arn" "$image_ref"
}

echo "Building images"
VERSION_XARGS="--build-arg BUILD_VERSION=${BUILD_VERSION} --build-arg UBI_VERSION=${UBI_VERSION}"
# Use Docker format (not OCI) for ECR scanning compatibility
BUILD_XARGS="--no-cache --progress=plain --output type=docker $VERSION_XARGS" # DEBUG ARGUMENTS
# BUILD_XARGS="$VERSION_XARGS" # REGULAR ARGUMENTS

echo "Building C3 UBI image"
C3_UBI_TAG="c3-ubi:$UBI_VERSION"
if ecr_tag_exists "c3-ubi" "$UBI_VERSION"; then
    echo "ECR image exists: $C3_UBI_TAG; pulling instead of building"
    $DOCKER_CMD pull "$REGISTRY_URI/$C3_UBI_TAG"
    $DOCKER_CMD tag "$REGISTRY_URI/$C3_UBI_TAG" "$C3_UBI_TAG"
elif $DOCKER_CMD image inspect $C3_UBI_TAG >/dev/null 2>&1; then
    echo "Image $C3_UBI_TAG already exists locally"
    $DOCKER_CMD image inspect $C3_UBI_TAG
else
    $DOCKER_CMD build $BUILD_XARGS -f c3-ubi/Containerfile -t $C3_UBI_TAG .
fi

echo "Building C3 build image"
C3_BUILD_TAG="c3-build:$BUILD_VERSION"
$DOCKER_CMD build $BUILD_XARGS -f c3-build/Containerfile -t $C3_BUILD_TAG .

echo "Building C3 API image"
C3_API_TAG="c3-api:$BUILD_VERSION"
$DOCKER_CMD build $BUILD_XARGS -f c3-api/Containerfile -t $C3_API_TAG .

SKIP_PUSH=${SKIP_PUSH:-"false"}
if [ "$SKIP_PUSH" == "false" ]; then
    echo "Pushing images"
    if ecr_tag_exists "c3-ubi" "$UBI_VERSION"; then
        echo "ECR tag already exists and is immutable: c3-ubi:$UBI_VERSION; skipping push"
    else
        $DOCKER_CMD tag $C3_UBI_TAG $REGISTRY_URI/$C3_UBI_TAG
        $DOCKER_CMD push $REGISTRY_URI/$C3_UBI_TAG
        echo "Pushed image URI: $REGISTRY_URI/$C3_UBI_TAG"
        sign_image_if_enabled "c3-ubi" "$UBI_VERSION"
    fi
    echo "ECR URL: https://${AWS_REGION}.console.aws.amazon.com/ecr/repositories/private/${AWS_ACCOUNT_ID}/c3-ubi?region=${AWS_REGION}"

    $DOCKER_CMD tag $C3_API_TAG $REGISTRY_URI/$C3_API_TAG
    $DOCKER_CMD push $REGISTRY_URI/$C3_API_TAG
    echo "Pushed image URI: $REGISTRY_URI/$C3_API_TAG"
    sign_image_if_enabled "c3-api" "$BUILD_VERSION"
    echo "ECR URL: https://${AWS_REGION}.console.aws.amazon.com/ecr/repositories/private/${AWS_ACCOUNT_ID}/c3-api?region=${AWS_REGION}"
fi

echo "$VERSION_Z" > version.z.txt

echo "Build and push images completed for version $BUILD_VERSION"
echo "# Check the build image:"
echo "docker run -it --rm $C3_BUILD_TAG bash"

echo "# Run the API image:"
echo "docker run -it --rm -p 10274:10274 $C3_API_TAG"

##
popd
echo "Script[$0] completed"
