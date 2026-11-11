# typed: strict
# frozen_string_literal: true

module ArtifactRegistry
  class Domain
    class StorageRecords < GH::Domain::Base
      # Check if a repository is deployable
      #
      # @param repository_id [Integer] The repository ID to check deployability for
      # @return [Boolean]
      sig { params(repository_id: Integer).returns(T::Boolean) }
      def repository_deployable?(repository_id)
        ArtifactStorageRecord
          .joins(:artifact_metadata)
          .where(artifact_metadata: { repository_id: repository_id })
          .active
          .exists?
      end
    end
  end
end
