# typed: true
# frozen_string_literal: true

module GitHub
  module Config
    module InsightsConfig
      def insights_api_server_endpoint
        @insights_api_server_endpoint ||= GitHub.environment.fetch("INSIGHTS_API_ENDPOINT", GitHub.default_insights_api)
      end
      attr_writer :insights_api_server_endpoint

      def default_insights_api
        return default_local_insights_api if Rails.env.test?

        # We are in codespaces using insights codespaces
        return default_local_insights_api if Rails.env.development? && FeatureFlag.vexi.enabled?(:insights_api_local_development, default: false)
        # Proper url for production
        "https://insights.github.com"
      end

      def default_local_insights_api
        # Codespaces local development
        "http://localhost:5000"
      end

      def insights_staging_api_server_endpoint
        # We are in codespaces using insights codespaces
        return default_local_insights_api if Rails.env.development? && FeatureFlag.vexi.enabled?(:insights_api_local_development, default: false)
        # Proper url for staging
        "https://insights-api-staging.service.iad.github.net"
      end
    end
  end

  extend Config::InsightsConfig
end
