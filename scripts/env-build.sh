#!/usr/bin/env bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
pushd "$DIR/.."
echo "script [$0] started"
#!

echo "Building native executable for C3 CLI..."
pushd c3-cli
quarkus build --native --no-tests -Dquarkus.native.container-build=true
popd

echo "Building C3 web application..."
pushd c3-web
npm run build
popd

#!
popd
echo "script [$0] completed"
