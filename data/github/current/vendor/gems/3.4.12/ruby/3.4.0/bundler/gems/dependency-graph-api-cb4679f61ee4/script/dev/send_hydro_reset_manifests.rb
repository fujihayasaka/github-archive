#!/usr/bin/env ruby
#
# Script that creates and publishes a sample hydro message for a manifest reset event, used for local testing.
# This script assumes you have a local hydro service running (usually via `docker compose up`)
# Usage: script/dev/send_hydro_manifest_reset.rb

require_relative "../../config/environment" unless defined?(Rails)
require_relative "../../proto/hydro/schemas/github/dependencygraph/v1/reset_manifests_pb.rb"
require_relative "../../proto/hydro/schemas/github/v1/entities/repository_pb.rb"
require_relative "../../proto/hydro/schemas/github/v1/entities/request_context_pb.rb"
require_relative "../../proto/hydro/schemas/github/v1/entities/user_pb.rb"
require_relative "local_hydro_helpers.rb"

require "debug"

DependencyGraph.logger.info "Sending a sample reset manifests event"

# Create sample repository entity
repository = Hydro::Schemas::Github::V1::Entities::Repository.new(
  id: 1234,
  name: "test-org/test-repo"
)

# Create sample user/actor entity
actor = Hydro::Schemas::Github::V1::Entities::User.new(
  id: 5678,
  login: "test-user"
)

# Create sample owner entity
owner = Hydro::Schemas::Github::V1::Entities::User.new(
  id: 9012,
  login: "test-org"
)

# Create request context
request_context = Hydro::Schemas::Github::V1::Entities::RequestContext.new(
  request_id: "test-request-id"
)

# Create the main ResetManifests message
reset_manifests = Hydro::Schemas::Github::Dependencygraph::V1::ResetManifests.new(
  request_context: request_context,
  actor: actor,
  repository: repository,
  owner: owner,
  action: :RESET_ACTION_REDETECT,
  trigger: :RESET_TRIGGER_STAFFTOOLS
)

publish(reset_manifests.to_h,
  topic: "github.dependencygraph.v1.ResetManifests",
  schema: "hydro.schemas.github.dependencygraph.v1.ResetManifests",
  # Everything to the same partition, locally
  partition_key: 0
)
