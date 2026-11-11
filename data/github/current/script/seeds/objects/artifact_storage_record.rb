# frozen_string_literal: true

# Do not require anything here. If you need something else, require it in the method that needs it.

module Seeds
  module Objects
    class ArtifactStorageRecord
      def self.create(
        artifact_metadata:,
        registry_url: Faker::Internet.url,
        artifact_url: Faker::Internet.url,
        registry_repository_name: Faker::Lorem.word
      )
        ::ArtifactStorageRecord.create!(
          artifact_metadata: artifact_metadata,
          registry_url: registry_url,
          artifact_url: artifact_url,
          registry_repository_name: registry_repository_name
        )
      end
    end
  end
end
