#!/bin/bash

set -euxo pipefail

# Put commands here that will run one time after the Codespace/devcontainer is created.

GRN='\033[1;32m'
NC='\033[0m'

source /etc/profile.dependency-graph.sh

setfacl -bnR /workspaces/dependency-graph-api
chmod -R '=rwX' /workspaces/dependency-graph-api

echo -e "${GRN}==> Running script/bootstrap...${NC}"
/workspaces/dependency-graph-api/script/bootstrap
