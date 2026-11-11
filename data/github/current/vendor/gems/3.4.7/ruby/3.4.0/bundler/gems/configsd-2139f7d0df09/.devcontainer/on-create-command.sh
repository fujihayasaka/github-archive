#!/bin/bash
set -e

echo "Running goproxy init..."
/usr/local/share/goproxy-init.sh

echo "Running protoc init..."
/usr/local/share/protoc-init.sh

echo "Running go lint init..."
/usr/local/share/go-linter-init.sh

echo "Downloading go modules..."
go mod download

echo "Installing GitHub CLI kustomize extension..."
gh extension install github/gh-kustomize

ln -sf ruby/.ruby-version .ruby-version
