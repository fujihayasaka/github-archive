#!/bin/bash

set -euxo pipefail

source /etc/advisory-db-env.sh

# Fix BUNDLE_RUBYGEMS__PKG__GITHUB__COM environment variable for GitHub packages authentication
# This ensures the variable has the correct format: username:token
if [[ -n "${GITHUB_USER:-}" && -n "${GITHUB_TOKEN:-}" ]]; then
    export BUNDLE_RUBYGEMS__PKG__GITHUB__COM="${GITHUB_USER}:${GITHUB_TOKEN}"
    
    # Add to system environment file with sudo if it doesn't already exist
    if ! grep -q "BUNDLE_RUBYGEMS__PKG__GITHUB__COM" /etc/advisory-db-env.sh; then
        echo "# Fix BUNDLE_RUBYGEMS__PKG__GITHUB__COM environment variable" | sudo tee -a /etc/advisory-db-env.sh
        echo "export BUNDLE_RUBYGEMS__PKG__GITHUB__COM=\"\${GITHUB_USER}:\${GITHUB_TOKEN}\"" | sudo tee -a /etc/advisory-db-env.sh
    fi
fi
