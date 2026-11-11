# frozen_string_literal: true

# Do not require anything here. If you need something else, require it in the method that needs it.

module Seeds
  module Objects
    class ArtifactMetadata
      def self.create(
        owner:,
        repository:,
        attestation_id: Faker::Number.number(digits: 5),
        name: Faker::Lorem.word,
        version: "#{Faker::Number.number(digits: 1)}.#{Faker::Number.number(digits: 1)}.#{Faker::Number.number(digits: 1)}",
        digest: "sha256:#{SecureRandom.hex(32)}",
        status:
      )
        ::ArtifactMetadata.create!(
          owner: owner,
          repository: repository,
          attestation_id: attestation_id,
          name: name,
          version: version,
          digest: digest,
          status: status
        )
      end
    end
  end
end
