# typed: true
# frozen_string_literal: true

require "test_helper"

module SecretScanning::Models
  class RepoCountMetricTest < GitHub::TestCase

    context "from_proto" do
      test "returns model from proto definition" do
        proto = GitHub::Proto::SecretScanning::Metrics::V1::RepoCount.new(
          count: 50,
          repo_id: 199,
        )

        metric = RepoCountMetric.from_proto(proto)

        assert_equal 50, metric.count
        assert_equal 199, metric.repo_id
      end

    end
  end
end
