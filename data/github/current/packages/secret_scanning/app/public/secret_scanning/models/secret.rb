# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module SecretScanning
  module Models
    # Represents a detected secret
    class Secret
      sig { returns(String) }
      attr_reader :type
      sig { returns(String) }
      attr_reader :fingerprint
      sig { returns(T::Array[Location]) }
      attr_reader :locations
      sig { returns(TokenMetadata) }
      attr_reader :token_metadata
      sig { returns(T.nilable(String)) }
      attr_reader :bypass_placeholder_ksuid

      delegate :is_custom_pattern?, to: :token_metadata

      sig do
        params(type: String,
               fingerprint: String,
               locations: T::Array[Location],
               token_metadata: TokenMetadata,
               bypass_placeholder_ksuid: T.nilable(String)).void
      end
      def initialize(type: "", fingerprint: "", locations: [], token_metadata: TokenMetadata.new, bypass_placeholder_ksuid: nil)
        @type = type
        @fingerprint = fingerprint
        @locations = locations
        @token_metadata = token_metadata
        @bypass_placeholder_ksuid = bypass_placeholder_ksuid
      end

      sig { params(hash: T.nilable(Hash)).returns(Secret) }
      def self.from_hash(hash)
        return new if hash.nil?

        hash = hash.with_indifferent_access
        locations = T.let(hash[:locations] || [], T::Array[Hash])
        new(
          type: hash[:type] || "",
          fingerprint: hash[:fingerprint] || "",
          locations: locations.map { |p| Location.from_hash(p) },
          token_metadata: TokenMetadata.from_hash(hash[:token_metadata]),
          bypass_placeholder_ksuid: hash[:bypass_placeholder_ksuid] || ""
        )
      end
    end
  end
end
