#!/bin/bash

set -e

if [[ -f /usr/local/share/goproxy-init.sh ]]; then
  /usr/local/share/goproxy-init.sh
fi
