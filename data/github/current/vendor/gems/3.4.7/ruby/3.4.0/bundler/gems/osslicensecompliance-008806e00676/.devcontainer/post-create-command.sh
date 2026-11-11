#!/bin/bash

set -e

# Refresh the goproxy token on creation
if [[ -f /usr/local/share/goproxy-init.sh ]]; then
  /usr/local/share/goproxy-init.sh --override
fi

# Install the 'gh kustomize' tool for building k8s configuration from templates.
gh extension install github/gh-kustomize
