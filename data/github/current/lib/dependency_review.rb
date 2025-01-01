# typed: true
# frozen_string_literal: true

module DependencyReview
  autoload :HealthClient, "dependency_review/health_client"
  autoload :SnapshotClient, "dependency_review/snapshot_client"
  autoload :VulnerabilityHelper, "dependency_review/vulnerability_helper"
  autoload :PackageMetadataQuery, "dependency_review/package_metadata_query"
  autoload :ManifestLimitHelper, "dependency_review/manifest_limit_helper"
end
