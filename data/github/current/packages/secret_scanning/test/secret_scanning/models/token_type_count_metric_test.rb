# typed: true
# frozen_string_literal: true

require "test_helper"

module SecretScanning::Models
  class TokenTypeCountMetricTest < GitHub::TestCase

    context "from_proto" do
      test "returns model from proto definition" do
        proto = GitHub::Proto::SecretScanning::Metrics::V1::TokenTypeCount.new(
          count: 50,
          token_type: "CLOJARS_DEPLOY_TOKEN",
          token_metadata: GitHub::Proto::SecretScanning::Types::V1::TokenMetadata.new(
            token_type: "CLOJARS_DEPLOY_TOKEN",
            slug: "clojars_deploy_token",
            label: "Clojars Deploy Token",
            provider: "CLOJARS",
          )
        )

        token_type_count_metric = TokenTypeCountMetric.from_proto(proto)

        assert_equal 50, token_type_count_metric.count
        assert_equal "CLOJARS_DEPLOY_TOKEN", token_type_count_metric.token_type
        refute token_type_count_metric.token_metadata.nil?
        assert_equal "CLOJARS_DEPLOY_TOKEN", token_type_count_metric.token_metadata&.token_type
        assert_equal "clojars_deploy_token", token_type_count_metric.token_metadata&.slug
        assert_equal "Clojars Deploy Token", token_type_count_metric.token_metadata&.label
        assert_equal "CLOJARS", token_type_count_metric.token_metadata&.provider
      end

    end
  end
end
