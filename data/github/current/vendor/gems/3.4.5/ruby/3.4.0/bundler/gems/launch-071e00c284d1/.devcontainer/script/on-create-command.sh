#!/bin/bash

set -eo pipefail

# https://github.com/github/features/tree/afcd0f0aac73139f88293e1e7e160a5d2de6f947/src/goproxy#full-example-usage
/usr/local/share/goproxy-init.sh

# https://github.com/github/ABS/blob/1e37ef636f4e28826dc4f016c493d79d42964d69/paved-path/codespaces-terraform/scripts/dev_container_setup.sh
tfenv install 1.7.0
tfenv use 1.7.0
