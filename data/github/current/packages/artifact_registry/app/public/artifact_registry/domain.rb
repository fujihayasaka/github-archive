# typed: strict
# frozen_string_literal: true

module ArtifactRegistry
  class Domain < GH::Domain::Base
    accessor ArtifactRegistry::Domain::StorageRecords, :storage_records
    accessor ArtifactRegistry::Domain::DeploymentRecords, :deployment_records
  end
end
