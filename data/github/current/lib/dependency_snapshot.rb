# typed: true
# frozen_string_literal: true

module DependencySnapshot
  autoload :BaseClient, "dependency_snapshot/base_client"
  autoload :DependencySnapshotClient, "dependency_snapshot/dependency_snapshot_client"
  autoload :DependencySnapshotProvider, "dependency_snapshot/dependency_snapshot_provider"
  autoload :EntitySerializer, "dependency_snapshot/entity_serializer"
  autoload :SnapshotsServiceClient, "dependency_snapshot/snapshots_service_client"
  autoload :V2, "dependency_snapshot/v2"
  autoload :VulnerabilityHelper, "dependency_snapshot/vulnerability_helper"

  # Error classes to handle any errors the Twirp API returns.
  class Error < StandardError; end
  class NotFoundError < Error; end
  class CircuitBrokenError < Error; end
  class BadRequestError < Error; end
  class MalformedError < Error; end
end
