#!/bin/bash
set -e

echo "Running goproxy init --override..."
/usr/local/share/goproxy-init.sh --override

# We set REPO_ROOT here to ensure it is available for any code triggered
# by VS Code tasks or extensions.
export REPO_ROOT=$(git rev-parse --show-toplevel)
