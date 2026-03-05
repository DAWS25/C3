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

run_step "Build and push images" "./scripts/images-push.sh"
run_step "Deploy tenant tier" "./scripts/tenant-deploy.sh"
run_step "Deploy environment tier" "./scripts/env-deploy.sh"
run_step "Deploy services tier" "./scripts/services-deploy.sh"
run_step "Deploy distribution tier" "./scripts/distribution-deploy.sh"

echo
echo "Script [$0] completed"
popd >/dev/null