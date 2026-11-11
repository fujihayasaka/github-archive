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
    end
  end
end
