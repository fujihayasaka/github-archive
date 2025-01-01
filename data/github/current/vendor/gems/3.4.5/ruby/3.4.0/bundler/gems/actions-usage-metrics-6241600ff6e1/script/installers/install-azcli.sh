#!/bin/bash

set -e

if ! command -v az &>/dev/null; then
  echo "Installing az cli"
  curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
else
  echo "az already installed"
fi

az version
