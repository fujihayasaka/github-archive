# typed: strict
# frozen_string_literal: true

require "secret_scanning_proto"

module SecurityOverviewAnalytics
  module Serializers
    class SecretScanningAlert < ActiveJob::Serializers::ObjectSerializer
      extend T::Sig

      SERIALIZED_PROPERTY_KEY = "_gh_soa_secret_scanning_alert_json"
      TargetType = ::GitHub::Proto::SecretScanning::Metrics::V1::Alert

      sig { override.params(argument: T.untyped).returns(T::Boolean) }
      def serialize?(argument)
        argument.is_a?(TargetType)
      end

      sig { override.params(alert: TargetType).returns(T::Hash[T.untyped, T.untyped]) }
      def serialize(alert)
        super({ SERIALIZED_PROPERTY_KEY => TargetType.encode_json(alert) })
      end

      sig { override.params(hash: T::Hash[T.untyped, T.untyped]).returns(TargetType) }
      def deserialize(hash)
        encoded_json = hash[SERIALIZED_PROPERTY_KEY] || hash[SERIALIZED_PROPERTY_KEY.to_sym]
        TargetType.decode_json(encoded_json, { ignore_unknown_fields: true })
      end
    end
  end
end

Rails.application.config.active_job.custom_serializers << SecurityOverviewAnalytics::Serializers::SecretScanningAlert
