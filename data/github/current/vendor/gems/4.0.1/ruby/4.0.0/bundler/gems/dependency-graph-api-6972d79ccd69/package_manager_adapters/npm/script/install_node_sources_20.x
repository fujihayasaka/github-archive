#!/bin/bash

# Discussion, issues and change requests at:
#   https://github.com/nodesource/distributions
#
# Script to install the NodeSource Node.js 20.x repo onto a
# Debian or Ubuntu system.
#
# Based on the updated NodeSource distribution scripts.
#

set -e

export DEBIAN_FRONTEND=noninteractive

# Logger Function
log() {
    local message="$1"
    local type="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local color
    local endcolor="\033[0m"

    case "$type" in
        "info") color="\033[38;5;79m" ;;
        "success") color="\033[1;32m" ;;
        "error") color="\033[1;31m" ;;
        *) color="\033[1;34m" ;;
    esac

    echo -e "${color}${timestamp} - ${message}${endcolor}"
}

# Error handler function
handle_error() {
    local exit_code=$1
    local error_message="$2"
    log "Error: $error_message (Exit Code: $exit_code)" "error"
    exit $exit_code
}

# Function to check for command availability
command_exists() {
    command -v "$1" &> /dev/null
}

check_os() {
    if ! [ -f "/etc/debian_version" ]; then
        handle_error "1" "This script is only supported on Debian-based systems."
    fi
}

# Function to check architecture
check_arch() {
    local arch=$(dpkg --print-architecture)
    if [ "$arch" != "amd64" ] && [ "$arch" != "arm64" ] && [ "$arch" != "armhf" ]; then
        handle_error "1" "Unsupported architecture: $arch. Only amd64, arm64, and armhf are supported."
    fi
}

# Function to install prerequisites
install_pre_reqs() {
    log "Installing pre-requisites" "info"

    # Run 'apt-get update'
    if ! apt-get update -y; then
        handle_error "$?" "Failed to run 'apt-get update'"
    fi

    # Run 'apt-get install'
    if ! apt-get install -y apt-transport-https ca-certificates curl gnupg; then
        handle_error "$?" "Failed to install required packages"
    fi

    if ! mkdir -p /usr/share/keyrings; then
        handle_error "$?" "Failed to create /usr/share/keyrings directory"
    fi

    # Clean up old NodeSource configurations
    rm -f /usr/share/keyrings/nodesource.gpg || true
    rm -f /etc/apt/sources.list.d/nodesource.list || true
    rm -f /etc/apt/sources.list.d/nodesource.sources || true

    # Download and import the NodeSource signing key
    log "Adding the NodeSource signing key to your keyring..." "info"
    if ! curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /usr/share/keyrings/nodesource.gpg; then
        handle_error "$?" "Failed to download and import the NodeSource signing key"
    fi

    # Explicitly set the permissions to ensure the file is readable by all
    if ! chmod 644 /usr/share/keyrings/nodesource.gpg; then
        handle_error "$?" "Failed to set correct permissions on /usr/share/keyrings/nodesource.gpg"
    fi
}

# Function to configure the repository
configure_repo() {
    local node_version=$1
    local arch=$(dpkg --print-architecture)

    log "Creating apt sources list file for the NodeSource Node.js ${node_version} repo..." "info"

    cat <<EOF | tee /etc/apt/sources.list.d/nodesource.sources > /dev/null
Types: deb
URIs: https://deb.nodesource.com/node_${node_version}
Suites: nodistro
Components: main
Architectures: ${arch}
Signed-By: /usr/share/keyrings/nodesource.gpg
EOF

    # Node.js pinning configuration
    echo "Package: nodejs" | tee /etc/apt/preferences.d/nodejs > /dev/null
    echo "Pin: origin deb.nodesource.com" | tee -a /etc/apt/preferences.d/nodejs > /dev/null
    echo "Pin-Priority: 600" | tee -a /etc/apt/preferences.d/nodejs > /dev/null

    # Run 'apt-get update'
    log "Running 'apt-get update'..." "info"
    if ! apt-get update -y; then
        handle_error "$?" "Failed to run 'apt-get update'"
    fi

    log "Repository configured successfully." "success"
    log "To install Node.js, run: apt-get install nodejs -y" "info"
}

# Define Node.js version
NODE_VERSION="20.x"

# Check OS
check_os

# Check architecture
check_arch

# Main execution
install_pre_reqs || handle_error $? "Failed installing pre-requisites"
configure_repo "$NODE_VERSION" || handle_error $? "Failed configuring repository"

log "Node.js ${NODE_VERSION} repository setup complete!" "success"
