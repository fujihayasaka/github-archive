#!/bin/bash

# Clone the blackbird repo into the workspace
git clone https://github.com/github/blackbird /workspaces/github/blackbird

/workspaces/blackbird-mw/script/install-tools && echo \"machine goproxy.githubapp.com login nobody password $GITHUB_TOKEN\" >> $HOME/.netrc"
/workspaces/blackbird-mw/script/bootstrap
