#!/usr/bin/env bash
set -euo pipefail
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
pushd "$DIR/.." >/dev/null
echo "script [$0] started"

# Usage:
#   BASE_URL=https://local.c3.daws25.com ./scripts/health-check.sh
BASE_URL=${BASE_URL:-"http://127.0.0.1:10274"}

check_200() {
	local path="$1"
	local url="${BASE_URL}${path}"
	local code

	code=$(curl -sS -o /dev/null -w "%{http_code}" "$url")
	if [[ "$code" != "200" ]]; then
		echo "FAIL $url -> HTTP $code"
		exit 1
	fi

	echo "OK   $url -> HTTP 200"
}

check_200 "/api"
check_200 "/kapi"

popd >/dev/null
echo "script [$0] completed"
