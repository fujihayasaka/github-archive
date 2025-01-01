#!/bin/bash

set -euxo pipefail

# Put commands here that will run one time after the Codespace/devcontainer is created.

GRN='\033[1;32m'
NC='\033[0m'

source /etc/profile.dependency-graph.sh

echo -e "${GRN}==> Starting development containers${NC}"
/workspaces/dependency-graph-api/script/start-containers
