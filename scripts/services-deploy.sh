#!/usr/bin/env bash
set -euo pipefail

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
pushd "$DIR/.." >/dev/null
echo "Script [$0] started"

run_step() {
    local label="$1"
    local script_path="$2"

    if [[ ! -x "$script_path" ]]; then
        echo "ERROR: Required script is missing or not executable: $script_path"
        exit 1
    fi

    echo
    echo "==> $label"
    "$script_path"
}

run_step "Deploy services to ECS" "./scripts/services-deploy-ecs.sh"
run_step "Deploy services to EKS" "./scripts/services-deploy-eks.sh"

popd >/dev/null
echo "Script [$0] completed"
