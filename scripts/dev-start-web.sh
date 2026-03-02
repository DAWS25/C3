#!/usr/bin/env bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
pushd "$DIR/.."
echo "script [$0] started"
#!

echo "Starting C3 web"
pushd c3-web
npm run dev
popd

#!
popd
echo "script [$0] completed"
