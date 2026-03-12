#!/usr/bin/env bash
set -euo pipefail
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
pushd "$DIR/.."
echo "script [$0] started"
##

echo "Removing binaries, logs and temporary files"
rm -rf c3-api/target
rm -rf c3-web/node_modules
rm -rf c3-web/dist
rm -rf c3-web/.next
rm -rf c3-web/.cache
rm -rf c3-web/.parcel-cache
rm -rf c3-web/.nuxt
rm -rf c3-web/.vercel
rm -rf c3-web/.serverless
rm -rf c3-web/.aws-sam


##
popd
echo "script [$0] completed"
