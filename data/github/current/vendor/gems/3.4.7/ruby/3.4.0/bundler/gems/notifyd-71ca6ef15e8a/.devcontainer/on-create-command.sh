#!/bin/bash

set -e

/usr/local/share/goproxy-init.sh
/usr/local/share/go-linter-init.sh

# Log in to ghcr.io for prebuilds - see Prebuilds section in docs/development.md for more information
if [ -n "${CONTAINER_BUILDER_TOKEN:-}" ]; then
  echo "${CONTAINER_BUILDER_TOKEN}" | docker login ghcr.io -u ${GITHUB_USER} --password-stdin

  docker compose config --profiles | while read profile
  do
    echo "Building $profile container"
    docker compose --profile $profile up --force-recreate --build --no-start -V || echo "Failed to prebuild $profile"
  done
fi

# install kustomize extension
gh extension install github/gh-kustomize
