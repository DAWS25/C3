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
    AWS_PAGER="" aws route53 list-resource-record-sets --hosted-zone-id "$zone_id" --output json | \
        python3 -c '
import json
import subprocess
import sys

zone_id = sys.argv[1]
data = json.load(sys.stdin)
records = data.get("ResourceRecordSets", [])

apex_name = ""
for record in records:
    if record.get("Type") in ("SOA", "NS"):
        apex_name = record.get("Name", "")
        break

for record in records:
    record_name = record.get("Name", "")
    record_type = record.get("Type", "")
    if record_name == apex_name and record_type in ("SOA", "NS"):
        continue

    batch = {
        "Comment": "Cleanup records for hosted-zone stack deletion",
        "Changes": [
            {
                "Action": "DELETE",
                "ResourceRecordSet": record,
            }
        ],
    }

    subprocess.run(
        [
            "aws",
            "route53",
            "change-resource-record-sets",
            "--hosted-zone-id",
            zone_id,
            "--change-batch",
            json.dumps(batch),
        ],
        check=False,
    )
' "$zone_id"
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
