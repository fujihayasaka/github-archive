#!/bin/bash
set -e

# Check if the runtime submodule needs initialization
if [ ! -d "/workspaces/sweagentd/runtime/.git" ]; then
    echo "Runtime submodule not initialized. Initializing now..."
    
    # Initialize the submodule (this is safe and won't delete the directory)
    git submodule update --init --recursive
else
    echo "Runtime submodule already initialized."
fi

# Install or update runtime dependencies if needed
if [ ! -d "/workspaces/sweagentd/runtime/node_modules" ]; then
    echo "Installing runtime dependencies..."
    (cd /workspaces/sweagentd/runtime && npm install)
else
    echo "Runtime dependencies already installed."
fi
