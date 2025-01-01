#!/bin/sh

# This file is copied into the Codespace and sourced from either
# /etc/bash.bashrc or /etc/zsh/zshrc

GRN='\033[1;32m'
NC='\033[0m'

if [ -d /usr/local/go/bin ]; then
    export PATH="/usr/local/go/bin:$PATH"
fi

if [ -d "$HOME/go/bin" ]; then
    export PATH="$HOME/go/bin:$PATH"
fi

if [ -d "$HOME/.rbenv/bin" ]; then
    export PATH="$HOME/.rbenv/bin:$PATH"
    eval "$(rbenv init -)"
fi

# Displays a fun little message on the first time you open the terminal.
# We're allowed to have fun, right? This conditional is copied from /etc/bash.bashrc
if [ -t 1 ] && [ ! -f "$HOME/.config/vscode-dev-containers/first-run-notice-already-displayed" ]; then
    # shellcheck disable=SC2059
    printf "\n${GRN}Welcome to github/dependency-graph-api!${NC}\n"
    echo "Now you're cooking with Codespaces!"
fi

# Ensure the GitHub token for the Codespace is used as our token for authenticating with Bundler
# for installing internal gems.
export BUNDLE_RUBYGEMS__PKG__GITHUB__COM="token:$GITHUB_TOKEN"

if [ -f /etc/dg.codespace-compose ]; then
    export DG_CODESPACE_COMPOSE=1

    echo "This Codespace is configured to run in Codespace Compose mode!"

    # If we are running in codespace-compose, then use the server from the github/github codespace.
    export MONOLITH_API_PORT=3000
    export MONOLITH_API_URL="http://api.github.localhost:3000/internal"
else
    export DG_CODESPACE_COMPOSE=0

    # Set the monolith API URL to the local stub if we're *not* running in Codespace Compose mode.
    export MONOLITH_API_PORT=3859
    export MONOLITH_API_URL="http://localhost:$MONOLITH_API_PORT"
fi
