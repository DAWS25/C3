#!/usr/bin/env bash
set -euo pipefail
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
pushd "$DIR/.."
echo "script [$0] started"
##

TENANT_ID=${TENANT_ID:-"c3"}
ECR_SIGNING_ENABLED=${ECR_SIGNING_ENABLED:-"true"}
ECR_SIGNING_STACK_NAME=${ECR_SIGNING_STACK_NAME:-"${TENANT_ID}-ecr-signing-stack"}
ECR_SIGNING_PROFILE_NAME=${ECR_SIGNING_PROFILE_NAME:-"${TENANT_ID}_signing"}
ECR_SIGNING_PROFILE_NAME="${ECR_SIGNING_PROFILE_NAME//[^[:alnum:]_]/_}"
ECR_SIGNING_PROFILE_NAME="${ECR_SIGNING_PROFILE_NAME:0:64}"
if [[ ${#ECR_SIGNING_PROFILE_NAME} -lt 2 ]]; then
    ECR_SIGNING_PROFILE_NAME="c3_signing_profile"
fi
TENANT_DESTROY_TIMEOUT_SECONDS=${TENANT_DESTROY_TIMEOUT_SECONDS:-3600}
TENANT_DESTROY_POLL_SECONDS=${TENANT_DESTROY_POLL_SECONDS:-120}
TENANT_DESTROY_START_EPOCH=$(date +%s)
EB_APPLICATION_NAME=${EB_APPLICATION_NAME:-"${TENANT_ID}-api-app"}
EB_TERMINATE_TIMEOUT_SECONDS=${EB_TERMINATE_TIMEOUT_SECONDS:-1800}
EB_TERMINATE_POLL_SECONDS=${EB_TERMINATE_POLL_SECONDS:-30}

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

cleanup_elastic_beanstalk_application_versions() {
    local app_name="$1"
    local app_exists

    app_exists=$(aws elasticbeanstalk describe-applications \
        --application-names "$app_name" \
        --query "Applications[0].ApplicationName" \
        --output text 2>/dev/null || true)

    if [[ -z "$app_exists" || "$app_exists" == "None" ]]; then
        return
    fi

    echo "Cleaning Elastic Beanstalk application: $app_name"

    local active_env_ids
    active_env_ids=$(aws elasticbeanstalk describe-environments \
        --application-name "$app_name" \
        --no-include-deleted \
        --query "Environments[?Status!='Terminated'].EnvironmentId" \
        --output text 2>/dev/null || true)

    if [[ -n "$active_env_ids" && "$active_env_ids" != "None" ]]; then
        echo "Terminating Elastic Beanstalk environments: $active_env_ids"
        for env_id in $active_env_ids; do
            aws elasticbeanstalk terminate-environment \
                --environment-id "$env_id" \
                --terminate-resources >/dev/null || true
        done

        local terminate_start elapsed remaining_envs
        terminate_start=$(date +%s)
        while true; do
            remaining_envs=$(aws elasticbeanstalk describe-environments \
                --application-name "$app_name" \
                --no-include-deleted \
                --query "Environments[?Status!='Terminated'].EnvironmentId" \
                --output text 2>/dev/null || true)

            if [[ -z "$remaining_envs" || "$remaining_envs" == "None" ]]; then
                break
            fi

            elapsed=$(( $(date +%s) - terminate_start ))
            if (( elapsed >= EB_TERMINATE_TIMEOUT_SECONDS )); then
                echo "ERROR: Timeout terminating Elastic Beanstalk environments for app $app_name"
                echo "Still active environments: $remaining_envs"
                return 1
            fi

            sleep "$EB_TERMINATE_POLL_SECONDS"
        done
    fi

    local version_labels
    version_labels=$(aws elasticbeanstalk describe-application-versions \
        --application-name "$app_name" \
        --query "ApplicationVersions[].VersionLabel" \
        --output text 2>/dev/null || true)

    if [[ -n "$version_labels" && "$version_labels" != "None" ]]; then
        echo "Deleting Elastic Beanstalk application versions for $app_name"
        for version_label in $version_labels; do
            aws elasticbeanstalk delete-application-version \
                --application-name "$app_name" \
                --version-label "$version_label" \
                --delete-source-bundle >/dev/null || true
        done
    fi
}

verify_signing_profile_deleted() {
    if [[ "$ECR_SIGNING_ENABLED" != "true" ]]; then
        return
    fi

    echo "Verifying Signer profile deletion: $ECR_SIGNING_PROFILE_NAME"

    local profile_name
    profile_name=$(aws signer get-signing-profile \
        --profile-name "$ECR_SIGNING_PROFILE_NAME" \
        --query "profileName" \
        --output text 2>/dev/null || true)

    if [[ -n "$profile_name" && "$profile_name" != "None" ]]; then
        echo "ERROR: Signer profile still exists after signer stack deletion: $ECR_SIGNING_PROFILE_NAME"
        return 1
    fi

    echo "Signer profile not found: $ECR_SIGNING_PROFILE_NAME"
}

# Delete all stacks whose name starts with TENANT_ID in reverse order of creation.

while true; do    
    elapsed=$(( $(date +%s) - TENANT_DESTROY_START_EPOCH ))
    if (( elapsed >= TENANT_DESTROY_TIMEOUT_SECONDS )); then
        REMAINING_STACKS=$(aws cloudformation list-stacks --query "StackSummaries[?(starts_with(StackName, '$TENANT_ID') || StackName=='$ECR_SIGNING_STACK_NAME') && StackStatus!='DELETE_COMPLETE'].StackName" --output text || true)
        echo "ERROR: Tenant destroy timed out after ${TENANT_DESTROY_TIMEOUT_SECONDS}s"
        echo "Remaining stacks: ${REMAINING_STACKS:-none}"
        exit 1
    fi

    cleanup_tenant_hosted_zone_records
    cleanup_elastic_beanstalk_application_versions "$EB_APPLICATION_NAME"

    BUCKETS=$(aws s3api list-buckets --query "Buckets[?starts_with(Name, '$TENANT_ID')].Name" --output text)
    if [ -n "$BUCKETS" ]; then
        echo "Emptying buckets: $BUCKETS"
        for BUCKET in $BUCKETS; do
            echo "Emptying bucket: $BUCKET"
            aws s3 rm "s3://$BUCKET" --recursive || true
        done
    fi

    STACKS=$(aws cloudformation list-stacks --query "StackSummaries[?(starts_with(StackName, '$TENANT_ID') || StackName=='$ECR_SIGNING_STACK_NAME') && StackStatus!='DELETE_COMPLETE'].StackName" --output text | sort -r)
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
    sleep "$TENANT_DESTROY_POLL_SECONDS"
done

verify_signing_profile_deleted

popd
echo "script [$0] completed"
