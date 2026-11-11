# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

require "secret_scanning_proto"

module SecretScanning
  module Models
    class Bypass
      attr_reader :token_type, :reason, :expire_at

      sig do
        params(expire_at: T.nilable(Time),
               token_type: String,
               reason: Symbol).void
      end
      def initialize(expire_at:, token_type:, reason:)
        @expire_at = expire_at
        @token_type = token_type
        @reason = reason
      end

      sig { params(proto_type: GitHub::Proto::SecretScanning::Scans::V1::Bypass).returns(SecretScanning::Models::Bypass) }
      def self.from_proto(proto_type)
        SecretScanning::Models::Bypass.new(
          expire_at: proto_type.expire_at&.to_time,
          token_type: proto_type.token_type,
          reason: SecretScanning::Models::BypassReason.from_proto(T.cast(proto_type.reason, Symbol)),
        )
      end
    end
  end
end
