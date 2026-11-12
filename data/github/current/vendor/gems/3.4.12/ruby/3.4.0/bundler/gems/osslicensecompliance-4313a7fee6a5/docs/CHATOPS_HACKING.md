# Hacking Chatops

This guide is setup to help someone configure Hubot and the sample chatops rpc server in this project.

We used codespaces for this example so several steps here may not apply if you use them on MacOS.

## Guide
1. Clone and setup `github/hubot-classic` repo on your computer:
   ```
   git clone https://github.com/github/hubot-classic
   ```
1. You need a current version of xcode if you are on MacOS:
   ```
    # if updating run the sudo rm -rf /Library/Developer/CommandLineTools
    sudo rm -rf /Library/Developer/CommandLineTools
    xcode-select --install
   ```
1. You'll need a current version of python to allow hubot dependencies to build in npm. You can use [https://github.com/pyenv/pyenv](https://github.com/pyenv/pyenv#basic-github-checkout):
   ```
   git clone https://github.com/pyenv/pyenv.git ~/.pyenv
   cd ~/.pyenv && src/configure && make -C src
   ```
   On MacOS you can install `pyenv` with:
   ```
   brew update
   brew install pyenv
   brew install openssl readline sqlite3 xz zlib
   ```
1. Verify `pyenv` is working:
   ```
   git clone https://github.com/pyenv/pyenv-doctor.git "$(pyenv root)/plugins/pyenv-doctor"
   pyenv doctor
   ```
1. Find the next to latest version of python and install it:
   ```
   # get the latest version -1
   pyenv install --list | grep "^  3\.*"|tail -3|head -1
   pyenv install 3.10.3
   pyenv global 3.10.3
   ```
1. Download the `nodenv` installer, this is likely only needed in codespaces:
   ```
   curl -fsSL https://raw.githubusercontent.com/nodenv/nodenv-installer/master/bin/nodenv-installer | bash
   ```
1. Setup `node` with `nodenv`:
   ```
   export PATH="$HOME/.nodenv/bin:$PATH"
   export PATH="$HOME/.nodenv/shims:$PATH"
   export NODENV_VERSION="v$(< .node-version)"
   nodenv install
   echo "node `node --version`, npm `npm --version`"
   ```
1. Verify `node` installed:
   ```
   curl -fsSL https://raw.githubusercontent.com/nodenv/nodenv-installer/master/bin/nodenv-doctor | bash
   ```
1. Run `github/hubot-classic` bootstrap:
   ```
   ./script/bootstrap
   ```
   Note you might have to update the script to update this section:
   ```
   export PATH="/usr/local/share/nodenv/shims:$PATH"
   npm="npm"
   npm config set python "/usr/bin/python3.7"
   ```
   It should look like this on codespaces:
   ```
   export PATH="/usr/local/share/nodenv/shims:$PATH"
   npm="npm"
   npm config set python "/usr/bin/python3.7"
   ```
1. Make sure docker is working (if not start it): `docker info`
1. Start supporting services (mysql & redis): `docker-compose up`. This won't be needed on MacOS
1. Setup RPC by copying `./config/chatops-rpc/development.yaml.example` to `./config/chatops-rpc/development.yaml`
1. Setting up `github/hubot-classic` environment variables:
   ```
   export RPC_DEBUG=true # this setting is optional and useful for detecting event issues
   export HUBOT_ENVIRONMENT=development
   export RPC_SKIP_SSL_CHECK=1
   export RPC_PRIVATE_KEY=$(<./test/hubot-test.pem)

   # setup remaining env config
   cp .env.development .env.local
   ```
1. Start the hubot controller: `./script/server -debug`
1. Switch to the `github/osscompliance-service` repo and start the RPC server:
   ```
   export CHATOPS_AUTH_PUBLIC_KEY=$(<../hubot-classic/test/hubot-test.pub)
   go run cmd/chatops/main.go
   ```
1. Run chatops command in the hubot controller, such as `.oss ping`
