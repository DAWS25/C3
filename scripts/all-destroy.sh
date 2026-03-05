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

# Reverse dependency order for safe teardown.
run_step "Destroy distribution tier" "./scripts/distribution-destroy.sh"
run_step "Destroy services tier" "./scripts/services-destroy.sh"
run_step "Destroy environment tier" "./scripts/env-destroy.sh"
run_step "Destroy tenant tier" "./scripts/tenant-destroy.sh"

echo
echo "Script [$0] completed"
popd >/dev/null