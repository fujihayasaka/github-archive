# typed: strict
# frozen_string_literal: true

require "test_helper"
require "turboscan"

module SecurityOverviewAnalytics
  module Serializers
    class TurboscanInsightsAlertTest < GitHub::TestCase

      TargetType = ::Turboscan::Proto::InsightsAlert

      test "can serialize and deserialize alert payload" do
        alert = create_alert(repository_id: 123, alert_number: 1)
        serialized_payload = TurboscanInsightsAlert.serialize(alert)
        refute_nil serialized_payload[TurboscanInsightsAlert::SERIALIZED_PROPERTY_KEY]
        assert_equal alert, TurboscanInsightsAlert.deserialize(serialized_payload)
      end

      test "can deserialize encoded json" do
        alert = create_alert(repository_id: 123, alert_number: 1)
        payload = { TurboscanInsightsAlert::SERIALIZED_PROPERTY_KEY => TargetType.encode_json(alert) }
        assert_equal alert, TurboscanInsightsAlert.deserialize(payload)
      end

      test "can deserialize encoded json with a symbol key" do
        alert = create_alert(repository_id: 123, alert_number: 1)
        payload = { TurboscanInsightsAlert::SERIALIZED_PROPERTY_KEY.to_sym => TargetType.encode_json(alert) }
        assert_equal alert, TurboscanInsightsAlert.deserialize(payload)
      end

      test "can deserialize encoded json with unknown properties" do
        alert = create_alert(repository_id: 123, alert_number: 1)
        payload = {
          TurboscanInsightsAlert::SERIALIZED_PROPERTY_KEY => TargetType.encode_json(alert).gsub("ruleName", "ruleNameTest")
        }
        refute_equal alert, TurboscanInsightsAlert.deserialize(payload)

        alert.rule_name = ""
        assert_equal alert, TurboscanInsightsAlert.deserialize(payload)
      end

      private

      sig { params(repository_id: Integer, alert_number: Integer, kwargs: T.untyped).returns(TargetType) }
      def create_alert(repository_id:, alert_number:, **kwargs)
        t = Google::Protobuf::Timestamp.new(seconds: Time.now.utc.to_i)

        kwargs = {
          id: alert_number,
          repository_id:,
          created_at: t,
          updated_at: t,
          resolution: :NO_RESOLUTION,
          rule_name: "Uncontrolled data used in path expression",
          rule_sarif_identifier: "rb/path-injection",
          tool_name: "CodeQL",
          severity: :HIGH,
          closed_at: nil,
          closed: false,
          present_on_default_ref: true,
          **kwargs,
        }

        TargetType.new(**T.unsafe(kwargs))
      end
    end
  end
end
