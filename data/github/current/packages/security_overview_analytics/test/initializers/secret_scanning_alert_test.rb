# typed: true
# frozen_string_literal: true

require "test_helper"
require "secret_scanning_proto"

module SecurityOverviewAnalytics
  module Serializers
    class SecretScanningAlertTest < GitHub::TestCase

      TargetType = ::GitHub::Proto::SecretScanning::Metrics::V1::Alert

      test "can serialize and deserialize alert payload" do
        alert = create_alert(repository_id: 123, alert_number: 1)
        serialized_payload = SecretScanningAlert.serialize(alert)
        refute_nil serialized_payload[SecretScanningAlert::SERIALIZED_PROPERTY_KEY]
        assert_equal alert, SecretScanningAlert.deserialize(serialized_payload)
      end

      test "can deserialize encoded json" do
        alert = create_alert(repository_id: 123, alert_number: 1)
        payload = { SecretScanningAlert::SERIALIZED_PROPERTY_KEY => TargetType.encode_json(alert) }
        assert_equal alert, SecretScanningAlert.deserialize(payload)
      end

      test "can deserialize encoded json with a symbol key" do
        alert = create_alert(repository_id: 123, alert_number: 1)
        payload = { SecretScanningAlert::SERIALIZED_PROPERTY_KEY.to_sym => TargetType.encode_json(alert) }
        assert_equal alert, SecretScanningAlert.deserialize(payload)
      end

      test "can deserialize encoded json with unknown properties" do
        alert = create_alert(repository_id: 123, alert_number: 1)
        payload = {
          SecretScanningAlert::SERIALIZED_PROPERTY_KEY => TargetType.encode_json(alert).gsub("tokenTypeProvider", "tokenTypeProviderTest")
        }
        refute_equal alert, SecretScanningAlert.deserialize(payload)

        alert.token_type_provider = ""
        assert_equal alert, SecretScanningAlert.deserialize(payload)
      end

      private

      sig { params(repository_id: Integer, alert_number: Integer, kwargs: T.untyped).returns(TargetType) }
      def create_alert(repository_id:, alert_number:, **kwargs)
        t = Google::Protobuf::Timestamp.new(seconds: Time.now.utc.to_i)

        kwargs = {
          repository_id:,
          number: alert_number,
          created_at: t, # AnyTime # datetime(3) NOT NULL,
          updated_at: t, # AnyTime # datetime(3) NOT NULL,
          resolved: false, # T::Boolean # tinyint(1) NOT NULL,
          resolved_at: nil, # T.nilable(AnyTime) # datetime(3) DEFAULT NULL,
          resolution: nil, # T.nilable(Integer) # tinyint unsigned DEFAULT NULL,
          token_type: "cp_1", # String: varchar(64) COLLATE utf8mb4_unicode_520_ci NOT NULL,
          token_type_provider: "CP", # String: varchar(256) COLLATE utf8mb4_unicode_520_ci NOT NULL,
          slug: "custom_pattern", # String: varchar(256) COLLATE utf8mb4_unicode_520_ci NOT NULL,
          **kwargs,
        }

        TargetType.new(**T.unsafe(kwargs))
      end
    end
  end
end
