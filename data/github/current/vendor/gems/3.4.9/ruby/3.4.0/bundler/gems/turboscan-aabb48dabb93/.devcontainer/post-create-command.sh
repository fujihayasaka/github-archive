if [ -n "${CODESPACES:-}" ]; then
  # (Re)start SSH (if it hasn't been already)
  sudo /etc/init.d/ssh restart

  # Setup SSH keys (if not already done by e.g. dotfiles)
  if [ -z "$(cat /home/devuser/.ssh/authorized_keys 2>/dev/null)" ]; then
    echo "Downloading SSH keys..."
    curl --silent --fail "https://github.com/${GITHUB_USER}.keys" > /home/devuser/.ssh/authorized_keys
  fi
fi
