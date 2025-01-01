#!/bin/bash
set -e

gh kustomize >/dev/null 2>&1 || gh extension install github/gh-kustomize
