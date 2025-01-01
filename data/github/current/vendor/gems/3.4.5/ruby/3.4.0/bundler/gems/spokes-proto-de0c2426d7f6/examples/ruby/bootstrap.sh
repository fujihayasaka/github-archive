#!/bin/bash

set -e

cd "$(dirname "$0")"

bundle config set --local path deps/bundle
bundle install
