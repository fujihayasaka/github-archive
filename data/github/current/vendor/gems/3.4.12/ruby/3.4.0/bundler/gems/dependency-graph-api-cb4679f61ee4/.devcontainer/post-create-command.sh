#!/bin/bash

set -euxo pipefail

/usr/local/share/goproxy-init.sh

gh extension install github/gh-kustomize

go install github.com/twitchtv/twirp/protoc-gen-twirp@v8.1.0
go install github.com/arthurnn/twirp-ruby/protoc-gen-twirp_ruby@v1.11.0
go install github.com/interlynk-io/sbomqs@v0.0.12
go install github.com/CycloneDX/sbom-utility@v0.9.3
