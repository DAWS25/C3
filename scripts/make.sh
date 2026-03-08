#!/usr/bin/env bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
pushd "$DIR/.."
echo "script [$0] started"
##

pushd c3-web
echo "Building C3 web application dir[$(pwd)]"
npm install
npm run build
popd

pushd c3-api
echo "Building API image dir[$(pwd)]"
mvn
popd

##
popd
echo "script [$0] completed"

