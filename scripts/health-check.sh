#!/usr/bin/env bash
set -ex
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
pushd "$DIR/.."
echo "script [$0] started"
##

CURL_CMD="curl  "
BASE_URL="http://127.0.0.1:10274"

$CURL_CMD $BASE_URL/api
echo ""

$CURL_CMD $BASE_URL/api/q/health
echo ""

$CURL_CMD $BASE_URL/api/q/health/live
echo ""

$CURL_CMD $BASE_URL/api/q/health/ready
echo ""

$CURL_CMD $BASE_URL/api/q/health/started
echo ""

##
popd
echo "script [$0] completed"
