#!/bin/bash

# Clone the blackbird repo into the workspace
git clone https://github.com/github/blackbird /workspaces/blackbird

# Add Go Proxy credentials.
echo "machine goproxy.githubapp.com login nobody password $GITHUB_TOKEN" >> $HOME/.netrc

 # Run setup scripts.
/workspaces/blackbird-mw/script/install-tools
/workspaces/blackbird-mw/script/bootstrap

# Setup direnv hooks for installed shells

# Check and add for bash
if command -v bash >/dev/null; then
   BASHRC="$HOME/.bashrc"
   if [ -f "$BASHRC" ]; then
      if ! grep -q 'direnv hook bash' "$BASHRC"; then
         echo 'eval "$(direnv hook bash)"' >> "$BASHRC"
         echo "Added direnv hook to $BASHRC"
      else
         echo "direnv hook already exists in $BASHRC"
      fi
   else
      echo "$BASHRC not found. Please create it or add the following line manually:"
      echo 'eval "$(direnv hook bash)"'
   fi
fi

# Check and add for fish
if command -v fish >/dev/null; then
   FISH_CONFIG="$HOME/.config/fish/config.fish"
   if [ -f "$FISH_CONFIG" ]; then
      if ! grep -q 'direnv hook fish' "$FISH_CONFIG"; then
         echo 'eval (direnv hook fish)' >> "$FISH_CONFIG"
         echo "Added direnv hook to $FISH_CONFIG"
      else
         echo "direnv hook already exists in $FISH_CONFIG"
      fi
   else
      echo "$FISH_CONFIG not found. Please create it or add the following line manually:"
      echo 'eval (direnv hook fish)'
   fi
fi

direnv allow