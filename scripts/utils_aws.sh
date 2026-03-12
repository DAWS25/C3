#!/usr/bin/env bash

# Returns success if the given CloudFormation stack exists.
# Args: $1 = stack name
stack_exists() {
    local stack_name="$1"
    aws cloudformation describe-stacks --stack-name "$stack_name" >/dev/null 2>&1
}

# Prints the current CloudFormation stack status.
# Args: $1 = stack name
stack_status() {
    local stack_name="$1"
    aws cloudformation describe-stacks \
        --stack-name "$stack_name" \
        --query 'Stacks[0].StackStatus' \
        --output text 2>/dev/null || true
}

# Waits for stack deletion to complete with timeout and polling.
# Args: $1 = stack name, $2 = timeout seconds, $3 = poll interval seconds
wait_for_stack_delete_with_timeout() {
    local stack_name="$1"
    local timeout_seconds="$2"
    local poll_seconds="$3"
    local start_epoch elapsed status

    start_epoch=$(date +%s)
    while true; do
        if ! stack_exists "$stack_name"; then
            return 0
        fi

        status=$(stack_status "$stack_name")
        if [[ "$status" != "DELETE_IN_PROGRESS" ]]; then
            echo "Stack $stack_name current status: $status"
        fi

        elapsed=$(( $(date +%s) - start_epoch ))
        if (( elapsed >= timeout_seconds )); then
            echo "ERROR: Timeout waiting for stack deletion: $stack_name (${timeout_seconds}s)"
            return 1
        fi

        sleep "$poll_seconds"
    done
}

# Waits until a stack is no longer in an in-progress state.
# Deletes the stack first if it is stuck in ROLLBACK_COMPLETE.
# Args: $1 = stack name, $2 = poll interval seconds (optional, default 20)
wait_for_stack_ready() {
    local stack_name="$1"
    local poll_seconds="${2:-20}"
    local status

    status=$(stack_status "$stack_name")

    while [[ "$status" == *_IN_PROGRESS || "$status" == *_CLEANUP_IN_PROGRESS ]]; do
        echo "Stack $stack_name is $status; waiting for it to stabilize..."
        sleep "$poll_seconds"
        status=$(stack_status "$stack_name")
    done

    if [[ "$status" == "ROLLBACK_COMPLETE" ]]; then
        echo "Deleting rollback-complete stack: $stack_name"
        aws cloudformation delete-stack --stack-name "$stack_name"
        aws cloudformation wait stack-delete-complete --stack-name "$stack_name"
    fi
}

# Deletes the stack when it is in ROLLBACK_COMPLETE so it can be recreated.
# Args: $1 = stack name
delete_stack_if_rollback_complete() {
    local stack_name="$1"
    local status

    status=$(stack_status "$stack_name")
    if [[ "$status" == "ROLLBACK_COMPLETE" ]]; then
        echo "Deleting rollback-complete stack: $stack_name"
        aws cloudformation delete-stack --stack-name "$stack_name"
        aws cloudformation wait stack-delete-complete --stack-name "$stack_name"
    fi
}

# Safely deploys a stack after ensuring it's in a stable state.
# Args: $1 = stack name, remaining args = aws cloudformation deploy arguments
deploy_stack_safe() {
    local stack_name="$1"
    shift

    wait_for_stack_ready "$stack_name"
    aws cloudformation deploy --stack-name "$stack_name" "$@"
}
