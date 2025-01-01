#!/bin/bash
# This runs during prebuild, after the container image is built.
set -e

#initialize goproxy configuration
/usr/local/share/goproxy-init.sh

# initialize go-linter configuration
/usr/local/share/go-linter-init.sh

echo "Pre-pulling base docker images"
echo $GITHUB_TOKEN | docker login ghcr.io -u $USER --password-stdin
./script/pull-base-images || echo "❌ Failed to pull some base images" >&2

echo "Pre-download Go modules"
go mod download -x

echo "Pre-build"
go build -v ./...

echo "Bootstrap"
./script/bootstrap
