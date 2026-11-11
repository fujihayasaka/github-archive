# typed: true
# frozen_string_literal: true

require "faraday"
require "monolith-twirp-reposinsights-rulesinsights"

module RulesInsights
  module Twirp
    class RulesClient
      SERVICE_NAME = "rules_insights_github_client"

      # Do not instantiate this directly--use RulesInsights::Twirp.rules_client instead within the package,
      # or go through the RulesInsights domain layer for public use.
      def initialize(http_adapter: self.class.default_http_adapter)
        @http_adapter = http_adapter
        @twirp_client = MonolithTwirp::ReposInsights::RulesInsights::V1::RulesInsightsAPIClient.new(http_adapter)
      end

      sig { returns(MonolithTwirp::ReposInsights::RulesInsights::V1::PingResponse) }
      def ping
        response = twirp_client.ping(MonolithTwirp::ReposInsights::RulesInsights::V1::PingRequest.new)
        handle_error(response.error) if response.error
        response.data
      end

      def self.default_http_adapter
        GitHub::FaradayClient::Internal.new(url: GitHub.repos_insights_url) do |c|
          c.headers[:user_agent] = "github-#{GitHub.role}"
          c.options[:timeout] = 10
          c.request(:retry, max: 2)
          c.use GitHub::FaradayMiddleware::Datadog, stats: GitHub.dogstats, service_name: SERVICE_NAME
          c.adapter(:typhoeus)
        end
      end

      private

      def handle_error(error)
        GitHub.dogstats.increment("repos_insights.rules_insights.error", tags: ["code:#{error.code}"])

        exception = case error.code
        when :permission_denied
          PermissionDenied.new(error.msg)
        when :unavailable
          Unavailable.new(error.msg)
        when :internal
          Internal.new(error.msg)
        else
          Error.new(error.msg)
        end

        # Failbot is not compatible with Twirp error object.
        Failbot.report(exception)

        raise exception
      end

      sig { returns(GitHub::FaradayClient::Internal) }
      attr_reader :http_adapter

      sig { returns(MonolithTwirp::ReposInsights::RulesInsights::V1::RulesInsightsAPIClient) }
      attr_reader :twirp_client
    end
  end
end
