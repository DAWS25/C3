#!/bin/bash
set -euo pipefail

java -version
./mvnw -f ay clean install
mkdir -p bin/app/
cp -a ay/target/quarkus-app bin/


echo "Java build complete."