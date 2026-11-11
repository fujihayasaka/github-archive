# typed: true
# frozen_string_literal: true

require "faraday"
require "monolith-twirp-reposinsights-reposinsights"

module RepositoryInsights
  module Twirp
    class TrafficClient
      SERVICE_NAME = "repository_insights_github_client"

      # Do not instantiate this directly--use RepositoryInsights::Twirp.traffic_client instead within the package,
      # or RepositoryInsights.domain.traffic_for_repo for public use.
      def initialize(http_adapter: self.class.default_http_adapter)
        @http_adapter = http_adapter
        @twirp_client = MonolithTwirp::ReposInsights::ReposInsights::V1::ReposInsightsAPIClient.new(http_adapter)
      end

      sig { params(repo_id: Integer).returns(MonolithTwirp::ReposInsights::ReposInsights::V1::GetRepoTrafficResponse) }
      def get_repo_traffic_data(repo_id)
        response = twirp_client.get_repo_traffic(MonolithTwirp::ReposInsights::ReposInsights::V1::GetRepoTrafficRequest.new(repository_id: repo_id.to_s))

        if response.error
          handle_error(response.error)
        end

        MonolithTwirp::ReposInsights::ReposInsights::V1::GetRepoTrafficResponse.decode(response.body)
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
        GitHub.dogstats.increment("repos.traffic.error", tags: ["code:#{error.code}"])

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

      sig { returns(MonolithTwirp::ReposInsights::ReposInsights::V1::ReposInsightsAPIClient) }
      attr_reader :twirp_client
    end
  end
end
