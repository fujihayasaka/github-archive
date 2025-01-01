#!/bin/bash
# This runs when the user starts up their codespace.
set -e

# reinitialize goproxy configuration
/usr/local/share/goproxy-init.sh --override

echo "Installing gh-kustomize"
./script/installers/install-gh-kustomize.sh
