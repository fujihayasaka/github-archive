#!/usr/bin/env ruby
#
# Script that creates and publishes a sample hydro message for manifest file changed, used for local testing.
# This script assumes you have a local hydro service running (usually via `docker compose up`)
# This script is the most interesting when you are also running `script/etl/repo_manifest_file_changes`
# Usage: bin/rails r script/dev/send_hydro_repository_manifest_file_change.rb <FILE>
unless defined?(Rails)
  puts "Don't call this script directly, use Rails Runner: `bin/rails r script/dev/send_hydro_repository_manifest_file_change.rb`"
  exit
end

require_relative "../../proto/hydro/schemas/github/dependencygraph/v0/repository_manifest_file_change_pb.rb"
require_relative "local_hydro_helpers.rb"
require "rainbow"

DependencyGraph.logger.info Rainbow("You can call this script with an argument that is a file path to load the manifest content with, or it will use the repo's Gemfile.lock by default.").yellow

dev_dir = File.expand_path(File.dirname(__FILE__))
manifest_file_path = File.join(dev_dir, "../../Gemfile.lock")
if ARGV.length > 0
  manifest_file_path = ARGV[0]
end

DependencyGraph.logger.info "Loading manifest: " + Rainbow(File.expand_path(manifest_file_path)).blue.bright

filename = File.basename(manifest_file_path)

payload = {
  repository_id: 1,
  owner_id: 1,
  repository_private: false,
  repository_fork: false,
  reopsitory_nwo: "github/somerepo",
  repository_stargazer_count: 1,
  manifest_file: {
    filename: filename,
    path: "somepath",
    git_ref: "someref",
    pushed_at: Time.now
  },
  is_backfill: false
}

manifest_file = {
  filename: payload[:manifest_file][:filename],
  path: payload[:manifest_file][:path],
  git_ref: payload[:manifest_file][:git_ref].to_s,
  pushed_at: payload[:manifest_file][:pushed_at],
}

message = {
  repository_id: payload[:repository_id],
  owner_id: payload[:owner_id],
  repository_private: payload[:repository_private],
  repository_fork: payload[:repository_fork],
  repository_nwo:  payload[:repository_nwo],
  repository_stargazer_count:  payload[:repository_stargazer_count],
  manifest_file: manifest_file,
  is_backfill: payload.fetch(:is_backfill, false),
}

publish(message,
  topic: "cp1-iad.ingest.github.dependencygraph.v1.RepositoryManifestFileChange",
  schema: "github.dependencygraph.v0.RepositoryManifestFileChange",
  partition_key: message[:repository_id])
