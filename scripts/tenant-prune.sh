#!/usr/bin/env bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
pushd "$DIR/.."
echo "script [$0] started"
##

TENANT_ID=${TENANT_ID:-"c3"}

# Delete all stacks whose name starts with $TENTANT_ID in reverse order of creation, repeat every minute until empty

while true; do    
    BUCKETS=$(aws s3api list-buckets --query "Buckets[?starts_with(Name, '$TENANT_ID')].Name" --output text)
    if [ -n "$BUCKETS" ]; then
        echo "Emptying buckets: $BUCKETS"
        for BUCKET in $BUCKETS; do
            echo "Emptying bucket: $BUCKET"
            aws s3 rm "s3://$BUCKET" --recursive || true
        done
    fi

    STACKS=$(aws cloudformation list-stacks --query "StackSummaries[?starts_with(StackName, '$TENANT_ID') && StackStatus!='DELETE_COMPLETE'].StackName" --output text | sort -r)
    if [ -z "$STACKS" ]; then
        echo "No stacks found, exiting"
        break
    fi
    echo "Deleting stacks: $STACKS"
    for STACK in $STACKS; do
        echo "Deleting stack: $STACK"
        aws cloudformation delete-stack --stack-name $STACK
    done
    echo "Waiting for stacks to be deleted..."
    sleep 60
done


## find  all scripts *.sh and chmod them to be executable
##
popd
echo "script [$0] completed"
