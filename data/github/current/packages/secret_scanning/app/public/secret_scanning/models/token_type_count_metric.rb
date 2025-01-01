# typed: strict
# frozen_string_literal: true

module SecretScanning
  module Models
    class TokenTypeCountMetric < T::Struct
      extend T::Sig

      prop :count, Integer
      const :token_type, String
      const :token_metadata, T.nilable(TokenMetadata)

      sig { params(proto: GitHub::Proto::SecretScanning::Metrics::V1::TokenTypeCount).returns(TokenTypeCountMetric) }
      def self.from_proto(proto)
        metadata = TokenMetadata.from_proto(T.must(proto.token_metadata)) if !proto.token_metadata.nil?

        TokenTypeCountMetric.new(
          count: proto.count,
          token_type: proto.token_type,
          token_metadata: metadata,
        )
      end
    end
  end
end
