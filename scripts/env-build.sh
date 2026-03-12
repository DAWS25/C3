#!/usr/bin/env bash
set -euo pipefail
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
pushd "$DIR/.."
echo "script [$0] started"
#!

# echo "Building native executable for C3 CLI..."
# pushd c3-cli
# ./mvnw package -Dnative -DskipTests -Dquarkus.native.container-build=true
# popd

echo "Building C3 web application..."
pushd c3-web
npm run build
popd

echo "Building and pushing C3 images"
./scripts/images-push.sh

#!
popd
echo "script [$0] completed"
