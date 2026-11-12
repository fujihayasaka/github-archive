#!/usr/bin/env bash
set -euo pipefail
[ -n "${DEBUG-}" ] && set -x
IFS=$'\n\t'

# onCreateCommand This command is the first of three (along with
#                 updateContentCommand and postCreateCommand) that finalizes
#                 container setup when a dev container is created. It and
#                 subsequent commands execute inside the container immediately
#                 after it has started for the first time. Cloud services can
#                 use this command when caching or prebuilding a container. This
#                 means that it will not typically have access to user-scoped
#                 assets or secrets.

cd "$(dirname "$0")/.."

# The codespaces-base image installed linux brew for us
echo "Initializing linuxbrew into bashrc and zprofile..."
echo 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"' >> "${HOME}/.bashrc"
echo 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"' >> "${HOME}/.zprofile"

# and rbenv
echo "Initializing rbenv into bashrc and zprofile..."
rbenv init bash || echo "bash shell not found for rbenv to init"
rbenv init zsh || echo "zsh shell not found for rbenv to init"

# setup the local repo
bundle install --local
script/setup