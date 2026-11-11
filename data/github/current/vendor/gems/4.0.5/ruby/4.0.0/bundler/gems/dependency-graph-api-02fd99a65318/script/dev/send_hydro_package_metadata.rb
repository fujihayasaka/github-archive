#!/usr/bin/env ruby
#
# Script that creates and publishes a sample hydro message for a package license gateway event, used for local testing.
# This script assumes you have a local hydro service running (usually via `docker compose up`)
# Usage: script/dev/send_hydro_package_metadata.rb <FILE>

# You can obtain a sample of the events from the package license gateway by running a query like this in data.githubapp.com:
#
#   SELECT coordinates, license_spdx_expression, uris, release_date, score, attributions
#   FROM hive_hydro.hydro.package_license_gateway_clearlydefined_v0_package_metadata
#   LIMIT 100;

require_relative "../../config/environment" unless defined?(Rails)
require_relative "../../proto/hydro/schemas/package_license_gateway/clearlydefined/v0/package_metadata_pb.rb"
require_relative "local_hydro_helpers.rb"

require "debug"

DependencyGraph.logger.info "You can call this script with an argument that is a file path to load the sample events from with, or it will use a list of sample events already generated."

dev_dir = File.expand_path(File.dirname(__FILE__))
sample_events_path = File.join(dev_dir, "sample_plg_events.json")
if ARGV.length > 0
  sample_events_path = ARGV[0]
end

DependencyGraph.logger.info "Loading events from file: #{sample_events_path}"
JSON.parse(File.read(sample_events_path)).each do |event|

  # Convert the release_date to a Time object since Twirp won't serialize the string-ed time for us
  event["release_date"] = Time.parse(event["release_date"]) unless event["release_date"].nil?

  publish(event,
    topic: "package_license_gateway.clearlydefined.v0.PackageMetadata",
    schema: "package_license_gateway.clearlydefined.v0.PackageMetadata",
    # Everything to the same partition, locally
    partition_key: 0
  )
end
