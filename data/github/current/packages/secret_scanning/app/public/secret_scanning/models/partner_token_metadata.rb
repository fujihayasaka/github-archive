# typed: strict
# frozen_string_literal: true

module SecretScanning
  module Models
    class PartnerTokenMetadata < T::Struct
      const :raw, String

      class MetadataPart < T::Struct
        const :key, String
        const :value, String

        sig do
          params(response: GitHub::Proto::SecretScanning::Api::V2::GetTokenMetadataResponse::TokenMetadata).returns(MetadataPart)
        end
        def self.from_proto(response)
          MetadataPart.new(key: response.key, value: response.value)
        end
      end

      const :metadata, T::Array[MetadataPart]

      sig do
        params(response: GitHub::Proto::SecretScanning::Api::V2::GetTokenMetadataResponse).returns(PartnerTokenMetadata)
      end
      def self.from_proto(response)
        PartnerTokenMetadata.new(
          raw: response.raw,
          metadata: response.metadata.map { |md| MetadataPart.from_proto(md) }
        )
      end
    end
  end
end
