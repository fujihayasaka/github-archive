#!/bin/bash

set -euxo pipefail

# Put commands here that will run one time after the Codespace/devcontainer is created.

GRN='\033[1;32m'
NC='\033[0m'

#####
# This script installs extra packages that are needed to develop locally.
#
eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
eval "$(rbenv init -)"

echo -e "${GRN}==> Running setup scripts...${NC}"
cd /workspaces/advisory-db
rbenv install
rbenv global "$(cat .ruby-version)"
bundle install

# Because both of these use running docker containers and we need to be on VPN to install from our common base image, we can't do these in prebuilds now. 
# script/bootstrap
# script/setup

# What DEV_FAST_LOOP=1 needs to run out of the box with prebuilds
sudo apt update
gem install ffi --version "$(cat Gemfile.lock | grep -Po '(?<=ffi \()[0-9]*\.[0-9]*\.[0-9]*')" -- --disable-system-libffi
echo | /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)"
/home/linuxbrew/.linuxbrew/bin/brew install node@20
echo 'export PATH="/home/linuxbrew/.linuxbrew/opt/node@20/bin:$PATH"' >> ~/.profile
source ~/.profile
npm install -g yarn
sudo mkdir /test
sudo chmod 666 /test
yarn install --ignore-engines
FAST_DEV_LOOP=1 bin/rake assets:precompile

echo -e "# enable linuxbrew \n eval \""'$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)'"\"" | sudo tee -a /etc/advisory-db-env.sh
eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
echo -e "# enable rbenv \n eval \""'$(rbenv init -)'"\"" | sudo tee -a /etc/advisory-db-env.sh

echo -e "# enable advisory-db shell \n source /etc/advisory-db-env.sh" | sudo tee -a /etc/bash.bashrc
echo -e "# enable advisory-db shell \n source /etc/advisory-db-env.sh" | sudo tee -a /etc/zsh/zshrc
