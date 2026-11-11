# frozen_string_literal: true

# Do not require anything here. If you need something else, require it in the method that needs it.

module Seeds
  module Objects
    class ArtifactDeploymentRecord
      def self.create(
        artifact_metadata:,
        logical_environment: "prod",
        deployment_name: Faker::Lorem.word,
        owner_id: artifact_metadata.owner.id
      )
        ::ArtifactDeploymentRecord.create!(
          artifact_metadata: artifact_metadata,
          logical_environment: logical_environment,
          deployment_name: deployment_name,
          owner_id: owner_id
        )
      end
    end
  end
end
