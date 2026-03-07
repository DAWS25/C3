#!/usr/bin/env bash
set -euo pipefail
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
pushd "$DIR/.."
echo "script [$0] started"
##

TENANT_ID=${TENANT_ID:-"c3"}

cleanup_tenant_hosted_zone_records() {
    local zone_stack="${TENANT_ID}-r53-zone-stack"
    local zone_id

    zone_id=$(aws cloudformation describe-stack-resources \
        --stack-name "$zone_stack" \
        --query "StackResources[?LogicalResourceId=='HostedZone'].PhysicalResourceId" \
        --output text 2>/dev/null || true)

    if [[ -z "$zone_id" || "$zone_id" == "None" ]]; then
        return
    fi

    echo "Cleaning hosted zone records before deletion: $zone_id"

    local apex_name
    local changes_count
    local query
    local delete_batch

    apex_name=$(aws route53 get-hosted-zone \
        --id "$zone_id" \
        --query "HostedZone.Name" \
        --output text)

    query="ResourceRecordSets[?!(Name=='${apex_name}' && (Type=='NS' || Type=='SOA'))]"

    changes_count=$(aws route53 list-resource-record-sets \
        --hosted-zone-id "$zone_id" \
        --query "length(${query})" \
        --output text)

    if [[ "$changes_count" == "0" ]]; then
        echo "No non-default records found in hosted zone: $zone_id"
        return
    fi

    delete_batch=$(aws route53 list-resource-record-sets \
        --hosted-zone-id "$zone_id" \
        --output json \
        --query "{Comment: 'Cleanup records for hosted-zone stack deletion', Changes: ${query}[].{Action: 'DELETE', ResourceRecordSet: @}}")

    aws route53 change-resource-record-sets \
        --hosted-zone-id "$zone_id" \
        --change-batch "$delete_batch"
}

# Delete all stacks whose name starts with TENANT_ID in reverse order of creation.

while true; do    
    cleanup_tenant_hosted_zone_records

    BUCKETS=$(aws s3api list-buckets --query "Buckets[?starts_with(Name, '$TENANT_ID')].Name" --output text)
    if [ -n "$BUCKETS" ]; then
        echo "Emptying buckets: $BUCKETS"
        for BUCKET in $BUCKETS; do
            echo "Emptying bucket: $BUCKET"
            aws s3 rm "s3://$BUCKET" --recursive || true
        done
    fi

    STACKS=$(aws cloudformation list-stacks --query "StackSummaries[?starts_with(StackName, '$TENANT_ID') && StackStatus!='DELETE_COMPLETE'].StackName" --output text | sort -r)
    if [[ -z "$STACKS" ]]; then
        echo "No stacks found, exiting"
        break
    fi
    echo "Deleting stacks: $STACKS"
    for STACK in $STACKS; do
        echo "Deleting stack: $STACK"
        aws cloudformation delete-stack --stack-name "$STACK"
    done
    echo "Waiting for stacks to be deleted..."
    sleep 60
done
popd
echo "script [$0] completed"
