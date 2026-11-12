#!/bin/sh

# This file is copied into the Codespace and sourced from either
# /etc/bash.bashrc or /etc/zsh/zshrc

GRN='\033[1;32m'
NC='\033[0m'

if [ -d /usr/local/go/bin ]; then
    export PATH="$PATH:/usr/local/go/bin"
fi

case "$PATH" in
*$HOME/go/bin*) GO_BIN=1 ;;
*             ) GO_BIN=0 ;;
esac

if [ "$GO_BIN" -eq "0" ]; then
    # Set the PATH to include the local go path, if it's not set already
    export PATH="$HOME/go/bin:$PATH"
fi

# Displays a fun little message on the first time you open the terminal.
# We're allowed to have fun, right? This conditional is copied from /etc/bash.bashrc
if [ -t 1 ] && [ ! -f "$HOME/.config/vscode-dev-containers/first-run-notice-already-displayed" ]; then
    # shellcheck disable=SC2059
    printf "\n${GRN}Welcome to github/dependency-snapshots-api!${NC}\n"
    echo "Takin' snapshots like it's going out of style!"
fi

if [ -f /etc/ds.codespace-compose ]; then
    export DS_CODESPACE_COMPOSE=1
else
    export DS_CODESPACE_COMPOSE=0
fi

if [ "$DS_CODESPACE_COMPOSE" = "1" ]; then
    echo "This Codespace is configured to run in Codespace Compose mode!"
fi
