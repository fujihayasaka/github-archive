# typed: strict
# frozen_string_literal: true

module SecretScanning::Util
  class PushProtectionFileUploads
    extend T::Sig

    sig { params(json_data: T.untyped).returns(T::Array[SecretScanning::Models::Secret]) }
    def self.secrets_from_json(json_data)
      secrets_as_json = json_data["secrets"]

      return [] unless secrets_as_json

      secrets = secrets_as_json.map do |secret|
        locations = T.let([], T::Array[SecretScanning::Models::Location])
        if secret["locations"].present?
          first_location = secret["locations"][0]
          first_location["path"] = json_data["file"]
          locations << SecretScanning::Models::Location.from_hash(first_location)
        end

        token_metadata = SecretScanning::Models::TokenMetadata.from_hash(secret["token_metadata"])

        SecretScanning::Models::Secret.new(
          type: secret["type"],
          fingerprint: secret["fingerprint"],
          locations: locations,
          token_metadata: token_metadata,
          bypass_placeholder_ksuid: secret["bypass_placeholder_ksuid"]
        )
      end

      secrets
    end
  end
end
