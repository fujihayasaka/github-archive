#!/bin/bash

# Push `dependencygraph.v1.RepositoryManifestFileChange` event for all detected repositories with `pnpm-lock.yaml` manifests

# Usage .transitions run <PR url> <environment> backfill_pnpm.sh [-w]

if [[ $# -eq 0 ]]; then
  # run in noop mode by default
  GOMEMLIMIT=1500MiB /src/app/backfill -v -noop -ecosystem pnpm -checkpoint-name backfill_pnpm
elif [ "$1" == "-w" ]; then
  GOMEMLIMIT=1500MiB /src/app/backfill -v -ecosystem pnpm -checkpoint-name backfill_pnpm
fi
