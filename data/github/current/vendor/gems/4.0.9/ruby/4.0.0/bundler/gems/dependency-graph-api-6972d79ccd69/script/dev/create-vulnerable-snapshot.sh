#!/bin/sh
# This script creates a vulnerable dependency snapshot, using the vulnerable packages that are part of
#  "Testing vulnerability data locally (with mock data)" from our README.

curl "http://localhost:9596/twirp/build-snapshots/DependencyGraphAPI.v1.DependencySnapshotAPI/CreateDependencySnapshot" \
-H 'Content-Type: application/json' \
-d \
'{
    "repository_id": 1,
    "repository_metadata": {
        "nwo": "monalisa/vulnerable-repo-1630352532",
        "owner_id": 1
    },
    "sha": "abcde12345678",
    "metadata": {
        "branch_ref": "refs/heads/main",
        "build_id": "1",
        "build_type": "workflow/build"
    },
    "scanned_at": "2021-08-29T23:38:24.268078000Z",
    "manifests": {
        "Gemfile.lock": {
            "graph": {
                "pkg:gem/octokit@4.11.0": {
                    "scope": 6,
                    "explicit": true,
                    "dependencies": []
                },
                "pkg:gem/multipart-post@2.1.0": {
                    "scope": 6,
                    "explicit": true,
                    "dependencies": []
                },
                "pkg:gem/faraday@0.13.0": {
                    "scope": 6,
                    "explicit": true,
                    "dependencies": []
                }
            }
        }
    }
}'
