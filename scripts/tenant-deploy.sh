#!/bin/bash
set -e
DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
pushd "$DIR/.."
echo "Script[$0] started"
##

export REPOSITORY_NAME="c3-ubi"
aws cloudformation deploy --stack-name ecr-$REPOSITORY_NAME \
    --template-file c3-cform/ecr-repository.cform.yaml \
    --parameter-overrides RepositoryName=$REPOSITORY_NAME

export REPOSITORY_NAME="c3-api"
aws cloudformation deploy --stack-name ecr-$REPOSITORY_NAME \
    --template-file c3-cform/ecr-repository.cform.yaml \
    --parameter-overrides RepositoryName=$REPOSITORY_NAME

##
popd
echo "Script[$0] completed"
