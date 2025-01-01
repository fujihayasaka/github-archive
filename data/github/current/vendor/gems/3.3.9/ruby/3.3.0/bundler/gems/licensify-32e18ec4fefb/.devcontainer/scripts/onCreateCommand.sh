#!/bin/bash

set -e

if [[ $GITHUB_REPOSITORY != "github/github" ]] && [ -z "$RAILS_ROOT" ]; then
  /usr/local/share/goproxy-init.sh
fi

# install go linter
/usr/local/share/go-linter-init.sh

# install Terraform
/workspaces/licensify/.devcontainer/scripts/install-terraform

