#!/bin/bash
# This runs during prebuild, after the container image is built.
set -e

# initialize goproxy configuration
/usr/local/share/goproxy-init.sh