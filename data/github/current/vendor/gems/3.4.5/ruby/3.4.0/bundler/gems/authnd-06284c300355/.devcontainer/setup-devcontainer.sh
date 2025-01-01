#!/bin/bash
set -e

git config --global credential.helper store
git config --global url."https://github.com/".insteadOf git@github.com:

# copy our welcome message
if [ -f "./.devcontainer/welcome-message.txt" ]; then
  sudo cp --force ./.devcontainer/welcome-message.txt /usr/local/etc/vscode-dev-containers/first-run-notice.txt
fi

# Wait for mysql startup
sleep 15s

# Make sure mysql can open its socket
sudo mkdir /var/run/mysqld && sudo chown mysql:mysql /var/run/mysqld
sudo chown mysql:mysql /etc/mysql/my.cnf
sudo chmod 600 /etc/mysql/my.cnf
sudo supervisorctl restart mysql

# Convert mysql root user to password auth instead of socket
sudo mysql -u root -e "ALTER USER \"root\"@\"localhost\" IDENTIFIED WITH mysql_native_password BY \"\""

# Bootstrap authnd dependencies
CODESPACES=true script/bootstrap

# Setup authnd dependencies
CODESPACES=true script/setup

# Prep the binaries so that future makes will be quicker
make all

git config --global --unset credential.helper

# Install go tools necessary for vscode-go
# Based on: https://github.com/microsoft/vscode-dev-containers/blob/78aaae4e78473697f61a9d8450f73fc6a2174d1a/containers/go/.devcontainer/library-scripts/go-debian.sh#L150
GO_TOOLS="\
    golang.org/x/tools/gopls@latest \
    honnef.co/go/tools/cmd/staticcheck@latest \
    golang.org/x/lint/golint@latest \
    github.com/mgechev/revive@latest \
    github.com/uudashr/gopkgs/v2/cmd/gopkgs@latest \
    github.com/ramya-rao-a/go-outline@latest \
    github.com/go-delve/delve/cmd/dlv@latest \
    github.com/golangci/golangci-lint/cmd/golangci-lint@latest"

echo "${GO_TOOLS}" | xargs -n 1 go install -v

rc_updates="$(cat << EOF
export GOPATH="$HOME/go"
if [[ "\${PATH}" != *"\${GOPATH}/bin"* ]]; then export PATH="\${PATH}:\${GOPATH}/bin"; fi
export GOROOT=$(dirname $GO_INSTALL_PATH)
if [[ "\${PATH}" != *"\${GOROOT}/bin"* ]]; then export PATH="\${PATH}:\${GOROOT}/bin"; fi
EOF
)"

# Add go tools to bashrc/zshrc
if [ -f /etc/bash.bashrc ]; then
  echo -e "$rc_updates" | sudo tee -a /etc/bash.bashrc
fi

if [ -f /etc/zshrc ]; then
  echo -e "$rc_updates" | sudo tee -a /etc/zshrc
fi