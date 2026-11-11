#!/bin/bash
# This runs when the user starts up their codespace.
set -e

# reinitialize goproxy configuration
/usr/local/share/goproxy-init.sh --override

# Set up runtime dependencies
cd "$(dirname "$0")/../runtime"
npm install

# Download autofind binary for code_review tool (if AUTOFIND_DOWNLOAD_GITHUB_TOKEN or GITHUB_TOKEN is available)
if [ -n "$AUTOFIND_DOWNLOAD_GITHUB_TOKEN" ] || [ -n "$GITHUB_TOKEN" ]; then
    echo "Downloading autofind binary for code_review tool..."
    runtime/script/autofind-build
else
    echo "AUTOFIND_DOWNLOAD_GITHUB_TOKEN or GITHUB_TOKEN not available, skipping autofind binary download."
    echo "Run 'runtime/script/autofind-build' manually with a GitHub token to set up the code_review tool."
fi
