if [ -n "${CODESPACES:-}" ]; then

  # Install full versions of packages for human use, not only the default "minimal" set.
  yes | sudo unminimize

  cd /workspaces/turboscan

  script/setup

  npm install

  make

fi
