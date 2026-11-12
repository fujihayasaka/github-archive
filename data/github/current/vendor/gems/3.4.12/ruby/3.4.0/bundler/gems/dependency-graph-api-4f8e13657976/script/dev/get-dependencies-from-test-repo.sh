#!/bin/sh
# This script gets the repository dependencies for the repo we created in create-vulnerable-snapshot.sh

curl "http://localhost:9596/twirp/repository-dependencies/DependencyGraphAPI.v1.RepositoryDependenciesAPI/GetDependenciesForRepository" \
-H 'Content-Type: application/json' \
-d \
'{
    "repository_id": 1
}'
