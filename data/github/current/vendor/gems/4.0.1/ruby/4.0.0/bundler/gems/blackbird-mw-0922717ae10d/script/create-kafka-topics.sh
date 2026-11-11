#!/bin/bash

set -e

# This script is used by Docker Compose to create all the kafka topics needed for the e2e tests.
#
# It uses --delete and --create to ensure the desired partition settings are applied.

if [[ "$#" -ne 1 ]]; then
  echo "Usage: $0 <server>"
  exit 1
fi

SERVER="$1"

declare -a pids
pids=()

start() {
  "$@" &
  pids+=($!)
}

wait_all() {
  for pid in "${pids[@]}"; do
    wait $pid
  done
  pids=()
}

# Arg is corpus (e.g. Brown)
create_doc_snapshot_topics() {
  start /usr/bin/kafka-topics --create --if-not-exists --topic blackbird.v1.GitDocument.$1.0 --partitions 2 --replication-factor 1 --bootstrap-server "${SERVER}"
  start /usr/bin/kafka-topics --create --if-not-exists --topic blackbird.v1.SnapshotTreeUpdate.$1.0 --partitions 1  --replication-factor 1 --bootstrap-server "${SERVER}"
}

# Arg is cluster (e.g. xi)
create_cluster_topics() {
  start /usr/bin/kafka-topics --create --if-not-exists --topic blackbird.v0.$1.ShardAssignment --partitions 1 --replication-factor 1 --bootstrap-server "${SERVER}"
  start /usr/bin/kafka-topics --create --if-not-exists --topic blackbird.v0.$1.ShardAssignmentSnapshot --partitions 1 --replication-factor 1 --bootstrap-server "${SERVER}"
}

create_source_topics() {
  start /usr/bin/kafka-topics --create --if-not-exists --topic blackbird.v0.BlackbirdOnboard --partitions 1 --replication-factor 1 --bootstrap-server "${SERVER}"
  start /usr/bin/kafka-topics --create --if-not-exists --topic cp1-iad.ingest.github.search.v0.RepositoryChanged --partitions 1 --replication-factor 1 --bootstrap-server "${SERVER}"
}

main() {
  echo 'Deleting old topics'
  start /usr/bin/kafka-topics --delete --if-exists --topic 'blackbird.*' --bootstrap-server "${SERVER}"
  start /usr/bin/kafka-topics --delete --if-exists --topic 'cp1-iad.ingest.github.search.v0.RepositoryChanged' --bootstrap-server "${SERVER}"
  wait_all

  echo 'Creating new topics in parallel'
  create_source_topics

  create_doc_snapshot_topics Yellow
  create_doc_snapshot_topics Green
  create_doc_snapshot_topics Blue
  create_doc_snapshot_topics Red
  create_doc_snapshot_topics Orange
  create_doc_snapshot_topics Cyan
  create_doc_snapshot_topics Magenta
  create_doc_snapshot_topics Brown

  create_cluster_topics xi
  create_cluster_topics nu
  create_cluster_topics mu
  create_cluster_topics lambda
  create_cluster_topics kappa
  create_cluster_topics iota
  create_cluster_topics theta
  create_cluster_topics eta
  create_cluster_topics zeta

  create_cluster_topics cache001
  create_cluster_topics cache002
  create_cluster_topics cache003
  create_cluster_topics cache004
  create_cluster_topics cache005
  create_cluster_topics cache006

  echo 'Waiting for all topics to be created'
  wait_all
  echo 'All topics have been created'
}

main
