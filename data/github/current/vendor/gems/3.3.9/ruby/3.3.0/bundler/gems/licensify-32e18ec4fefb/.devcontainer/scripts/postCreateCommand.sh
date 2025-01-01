#!/bin/bash

set -e

/usr/local/share/goproxy-init.sh --override

/workspaces/licensify/.devcontainer/scripts/setup-terraform
