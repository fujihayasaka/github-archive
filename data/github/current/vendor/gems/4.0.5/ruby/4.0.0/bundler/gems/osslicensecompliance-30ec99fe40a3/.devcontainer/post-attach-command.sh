#!/bin/bash

set -e

# Refresh the goproxy token each time the Codespace is opened
if [[ -f /usr/local/share/goproxy-init.sh ]]; then
  /usr/local/share/goproxy-init.sh --override
fi
