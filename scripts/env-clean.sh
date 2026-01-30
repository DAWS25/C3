#!/usr/bin/env bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
pushd "$DIR/.."
echo "script [$0] started"
#!

./mvnw -f c3-cli clean 

pushd c3-web
rm -rf build 
popd

#!
popd
echo "script [$0] completed"
