#!/bin/bash
# Causes a re-detection of all the `Package.resolved` manifests by
# publishing a `dependencygraph.v1.RepositoryManifestFileChange`
# event for all the Swift repositories where we have detected a
# manifest with such name.

GOMEMLIMIT=1500MiB /src/app/backfill -v -noop -ecosystem swift -checkpoint-name backfill_swift
