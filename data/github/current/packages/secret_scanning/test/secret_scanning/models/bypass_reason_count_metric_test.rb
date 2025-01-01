# typed: true
# frozen_string_literal: true

require "test_helper"

module SecretScanning::Models
  class BypassReasonCountMetricTest < GitHub::TestCase

    context "from_proto" do
      test "returns model from proto definition" do
        proto = GitHub::Proto::SecretScanning::Metrics::V1::BypassReasonCount.new(
          count: 10,
          bypass_reason: :FALSE_POSITIVE,
        )

        metric = BypassReasonCountMetric.from_proto(proto)

        assert_equal 10, metric.count
        assert_equal 0, metric.percent
        assert_equal :FALSE_POSITIVE, metric.bypass_reason
      end

    end
  end
end
