# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module SecretScanning
  module Models
    class TokenMetadata
      extend T::Sig

      sig { returns(String) }
      attr_reader :token_type
      sig { returns(String) }
      attr_reader :slug
      sig { returns(String) }
      attr_reader :label
      sig { returns(String) }
      attr_reader :provider

      sig do
        params(token_type: String,
               slug: String,
               label: String,
               provider: String).void
      end
      def initialize(token_type: "", slug: "", label: "", provider: "")
        @token_type = token_type
        @slug = slug
        @label = label
        @provider = provider
      end

      sig { returns(T::Boolean) }
      def is_custom_pattern?
        @provider.upcase == "CUSTOM_PATTERN" || @token_type.upcase.start_with?("CP_")
      end

      sig { params(proto: GitHub::Proto::SecretScanning::Types::V1::TokenMetadata).returns(TokenMetadata) }
      def self.from_proto(proto)
        new(
          token_type: proto.token_type,
          slug: proto.slug,
          label: proto.label,
          provider: proto.provider,
        )
      end

      sig { params(hash: T.nilable(Hash)).returns(TokenMetadata) }
      def self.from_hash(hash)
        return new if hash.nil?

        hash = hash.with_indifferent_access
        new(
          token_type: hash[:token_type] || "",
          slug: hash[:slug] || "",
          label: hash[:label] || "",
          provider: hash[:provider] || "",
        )
      end
    end
  end
end
