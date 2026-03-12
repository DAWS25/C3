#!/usr/bin/env bash
set -euo pipefail
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
pushd "$DIR/.."
echo "script [$0] started"
##

echo "Sanity check started"
aws --version
cdk --version
pushd ..
find .
popd
echo "Sanity check completed"

##
popd
echo "script [$0] completed"
