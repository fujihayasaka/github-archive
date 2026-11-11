# typed: strict
# frozen_string_literal: true

module ArtifactRegistry
  class Domain
    class DeploymentRecords < GH::Domain::Base
      # Check if a repository has active deployments
      #
      # @param repository_id [Integer] The repository ID to check deployments for
      # @return [Boolean]
      sig { params(repository_id: Integer).returns(T::Boolean) }
      def repository_deployed?(repository_id)
        ArtifactDeploymentRecord
          .joins(:artifact_metadata)
          .where(artifact_metadata: { repository_id: repository_id })
          .active
          .exists?
      end

      # Returns the distinct runtime-risk tag values for active deployment records
      # associated with the given repository.
      #
      # @param repository_id [Integer] The repository ID to get runtime risks for
      # @return [Array<String>] distinct runtime-risk values (e.g. ["internet-exposed", "sensitive-data"])
      sig { params(repository_id: Integer).returns(T::Array[String]) }
      def deployed_runtime_risks_for_repository(repository_id)
        ArtifactDeploymentRecord
          .joins(:artifact_metadata, :deployment_record_tags)
          .where(artifact_metadata: { repository_id: repository_id })
          .active
          .where(artifact_deployment_record_tags: { tag_name: "runtime-risk" })
          .distinct
          .pluck("artifact_deployment_record_tags.tag_value")
      end
    end
  end
end
