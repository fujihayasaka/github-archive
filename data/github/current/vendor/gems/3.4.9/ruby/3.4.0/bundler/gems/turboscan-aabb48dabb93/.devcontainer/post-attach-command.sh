#!/bin/bash
set -e

if [ -n "${CODESPACES:-}" ]; then

  # Set up hosts
  turboscan_hosts="127.0.0.1 db vtcombo kafka s3 elasticsearch azure redis aqueduct-lite"
  grep -qxF "$turboscan_hosts" /etc/hosts || echo "$turboscan_hosts" | sudo tee -a /etc/hosts > /dev/null

  echo "machine goproxy.githubapp.com login nobody password $GITHUB_TOKEN" > "$HOME/.netrc"
  
  echo "Running script/setup to start services..."
  script/setup

  # The remaining setup is taken from github/github


  # (Re)start SSH (if it hasn't been already)
  sudo /etc/init.d/ssh restart


  # Setup SSH keys (if not already done by e.g. dotfiles)
  if [ -z "$(cat /home/devuser/.ssh/authorized_keys 2>/dev/null)" ]; then
    echo "Downloading SSH keys..."
    CODESPACE_NAME="$(jq .CODESPACE_NAME /workspaces/.codespaces/shared/environment-variables.json -r)"
    # TODO: can we get/set this a better way?
    GITHUB_USERNAME="$(echo $CODESPACE_NAME | sed 's/-github-turboscan-.*//')"
    curl --silent --fail "https://github.com/${GITHUB_USERNAME}.keys" > /home/devuser/.ssh/authorized_keys
  fi

  # Setup ssh rc to run keep-alive command if not added by dotfiles
  if [ -z "$(cat /home/devuser/.ssh/rc 2>/dev/null)" ]; then
    mkdir -p /home/devuser/.ssh/
    cp $(pwd)/.devcontainer/sshrc /home/devuser/.ssh/rc
  fi

  # Setup ssh environment
  cat /workspaces/.codespaces/shared/.user-secrets.json | jq -r '.[] | select (.type=="EnvironmentVariable") | .name+"="+.value' > $HOME/.ssh/environment
  echo "PATH=/usr/local/go/bin:$PATH" >> $HOME/.ssh/environment

  # Run any additional user-specific hooks (if not already run)
  if ! [ -f /workspaces/.codespaces/.persistedshare/.codespaces-post-start-run ]; then
    for i in /workspaces/.codespaces/.persistedshare/dotfiles/script/codespaces-post-start \
             /workspaces/.codespaces/.persistedshare/dotfiles/codespaces-post-start; do
      if [ -f "$i" ] && [ -x "$i" ]; then
        echo "Running $i..."
        "$i"
        touch /workspaces/.codespaces/.persistedshare/.codespaces-post-start-run
        break
      fi
    done
  fi
fi

make build

# .bashrc/.zshrc snippet
user_rc_path="/home/devuser"

rc_snippet="$(cat << 'EOF'

if [ -z "${USER}" ]; then export USER=$(whoami); fi
if [[ "${PATH}" != *"$HOME/.local/bin"* ]]; then export PATH="${PATH}:$HOME/.local/bin"; fi

# Display optional first run image specific notice if configured and terminal is interactive
if [ -t 1 ] && [[ "${TERM_PROGRAM}" = "vscode" || "${TERM_PROGRAM}" = "codespaces" ]] && [ ! -f "$HOME/.config/vscode-dev-containers/first-run-notice-already-displayed" ]; then
    if [ -f "/usr/local/etc/vscode-dev-containers/first-run-notice.txt" ]; then
        cat "/usr/local/etc/vscode-dev-containers/first-run-notice.txt"
    elif [ -f "/workspaces/.codespaces/shared/first-run-notice.txt" ]; then
        cat "/workspaces/.codespaces/shared/first-run-notice.txt"
    fi
    mkdir -p "$HOME/.config/vscode-dev-containers"
    # Mark first run notice as displayed after 10s to avoid problems with fast terminal refreshes hiding it
    ((sleep 10s; touch "$HOME/.config/vscode-dev-containers/first-run-notice-already-displayed") &)
fi

# Set the default git editor if not already set
if [ -z "$(git config --get core.editor)" ] && [ -z "${GIT_EDITOR}" ]; then
    if  [ "${TERM_PROGRAM}" = "vscode" ]; then
        if [[ -n $(command -v code-insiders) &&  -z $(command -v code) ]]; then
            export GIT_EDITOR="code-insiders --wait"
        else
            export GIT_EDITOR="code --wait"
        fi
    fi
fi

# Enable autocompletion for git commands
source /usr/share/bash-completion/completions/git

EOF
)"

# Add RC snippet and custom bash prompt
if [ "${RC_SNIPPET_ALREADY_ADDED}" != "true" ]; then
    echo "${rc_snippet}" | sudo tee -a /etc/bash.bashrc
    echo 'export PROMPT_DIRTRIM=4' >> "${user_rc_path}/.bashrc"
    chown ${USERNAME}:${USERNAME} "${user_rc_path}/.bashrc"
fi
