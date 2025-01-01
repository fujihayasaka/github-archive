#!/bin/bash

set -e

if [[ $GITHUB_REPOSITORY != "github/github" ]] && [ -z "$RAILS_ROOT" ]; then
  /usr/local/share/goproxy-init.sh
fi

# Node installation
# https://github.com/nodesource/distributions#installation-instructions
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg

NODE_MAJOR=20
echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_$NODE_MAJOR.x nodistro main" | sudo tee /etc/apt/sources.list.d/nodesource.list

sudo apt-get update
sudo apt-get install nodejs -y

sudo npm install -g typescript
sudo npm link typescript

#protobuf
GO111MODULE=on

rm -rf /go/src/gotest.tools/gotestsum/
go install gotest.tools/gotestsum@latest

rm -rf /go/src/github.com/golang/protobuf
go install github.com/golang/protobuf/protoc-gen-go@latest

rm -rf /go/src/github.com/twitchtv/twirp
go install github.com/twitchtv/twirp/protoc-gen-twirp@latest

go install github.com/arthurnn/twirp-ruby/protoc-gen-twirp_ruby@latest

go install github.com/petergtz/pegomock/v4/pegomock@latest

go install github.com/mfridman/tparse@latest

/workspaces/billing-platform/.devcontainer/scripts/install-terraform

sudo apt-get update && \
    sudo apt-get -y install unzip netcat tmux

VERS="22.3"
ARCH="linux-x86_64"
ENDPOINT="https://github.com/protocolbuffers/protobuf/releases/download"

BIN_PATH=${PWD}/bin
mkdir -p ${BIN_PATH}
ZIP_NAME="protoc-${VERS}-${ARCH}.zip"

rm -rf ${BIN_PATH}/protoc
wget ${ENDPOINT}/v${VERS}/${ZIP_NAME} -O ${BIN_PATH}/${ZIP_NAME}
unzip ${BIN_PATH}/${ZIP_NAME} -d ${BIN_PATH}/tmp
mv ${BIN_PATH}/tmp/bin/protoc ${BIN_PATH}/protoc
rm ${BIN_PATH}/${ZIP_NAME}
rm -rf ${BIN_PATH}/tmp

PATH=${PATH}:${BIN_PATH}

# Pre-install Azure Cosmos DB Emulator for prebuilds
docker pull mcr.microsoft.com/cosmosdb/linux/azure-cosmos-emulator:latest
