# typed: true
# frozen_string_literal: true

require "faraday"
require "monolith-twirp-reposinsights-reposinsights"

module RepositoryInsights
  module Twirp
    class InsightsClient
      SERVICE_NAME = "repository_insights_github_client"

      # Do not instantiate this directly--use RepositoryInsights::Twirp.insights_client instead within the package,
      # or the corresponding RepositoryInsights.domain methods for public use.
      def initialize(http_adapter: self.class.default_http_adapter)
        @http_adapter = http_adapter
        @twirp_client = MonolithTwirp::ReposInsights::ReposInsights::V1::ReposInsightsAPIClient.new(http_adapter)
      end

      sig { params(repo_id: Integer).returns(MonolithTwirp::ReposInsights::ReposInsights::V1::GetRepoTrafficResponse) }
      def get_repo_traffic_data(repo_id)
        response = twirp_client.get_repo_traffic(MonolithTwirp::ReposInsights::ReposInsights::V1::GetRepoTrafficRequest.new(repository_id: repo_id.to_s))

        if response.error
          handle_error(response.error, metric: "repos.traffic.error")
        end

        MonolithTwirp::ReposInsights::ReposInsights::V1::GetRepoTrafficResponse.decode(response.body)
      end

      sig do
        params(network_id: String, default_oid: String)
          .returns(MonolithTwirp::ReposInsights::ReposInsights::V1::GetRepoContributorsResponse)
      end
      def get_repo_contributors(network_id:, default_oid:)
        response = twirp_client.get_repo_contributors(
          MonolithTwirp::ReposInsights::ReposInsights::V1::GetRepoContributorsRequest.new(
            network_id: network_id,
            default_oid: default_oid,
          ),
        )

        if response.error
          handle_error(response.error, metric: "repos.contributors.error")
        end

        MonolithTwirp::ReposInsights::ReposInsights::V1::GetRepoContributorsResponse.decode(response.body)
      end

      sig do
        params(network_id: String, default_oid: String, contributors_json: String)
          .returns(MonolithTwirp::ReposInsights::ReposInsights::V1::CreateRepoContributorsResponse)
      end
      def create_repo_contributors(network_id:, default_oid:, contributors_json:)
        response = twirp_client.create_repo_contributors(
          MonolithTwirp::ReposInsights::ReposInsights::V1::CreateRepoContributorsRequest.new(
            network_id: network_id,
            default_oid: default_oid,
            contributors_json: contributors_json,
          ),
        )

        if response.error
          handle_error(response.error, metric: "repos.contributors.error")
        end

        MonolithTwirp::ReposInsights::ReposInsights::V1::CreateRepoContributorsResponse.decode(response.body)
      end

      sig do
        params(network_id: String, default_oid: String, cache_date: String)
          .returns(MonolithTwirp::ReposInsights::ReposInsights::V1::GetRepoCommitActivityResponse)
      end
      def get_repo_commit_activity(network_id:, default_oid:, cache_date:)
        response = twirp_client.get_repo_commit_activity(
          MonolithTwirp::ReposInsights::ReposInsights::V1::GetRepoCommitActivityRequest.new(
            network_id: network_id,
            default_oid: default_oid,
            cache_date: cache_date,
          ),
        )

        if response.error
          handle_error(response.error, metric: "repos.commit_activity.error")
        end

        MonolithTwirp::ReposInsights::ReposInsights::V1::GetRepoCommitActivityResponse.decode(response.body)
      end

      sig do
        params(network_id: String, default_oid: String, commit_activity_json: String, cache_date: String)
          .returns(MonolithTwirp::ReposInsights::ReposInsights::V1::CreateRepoCommitActivityResponse)
      end
      def create_repo_commit_activity(network_id:, default_oid:, commit_activity_json:, cache_date:)
        response = twirp_client.create_repo_commit_activity(
          MonolithTwirp::ReposInsights::ReposInsights::V1::CreateRepoCommitActivityRequest.new(
            network_id: network_id,
            default_oid: default_oid,
            commit_activity_json: commit_activity_json,
            cache_date: cache_date,
          ),
        )

        if response.error
          handle_error(response.error, metric: "repos.commit_activity.error")
        end

        MonolithTwirp::ReposInsights::ReposInsights::V1::CreateRepoCommitActivityResponse.decode(response.body)
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

      def handle_error(error, metric:)
        handle_error_code(error.code, error.msg, metric: metric)
      end

      sig { params(code: T.any(String, Symbol), message: String, metric: String).returns(T.noreturn) }
      def handle_error_code(code, message, metric:)
        normalized_code = code.to_s
        GitHub.dogstats.increment(metric, tags: ["code:#{normalized_code}"])

        exception = case normalized_code
        when "permission_denied"
          PermissionDenied.new(message)
        when "unavailable"
          Unavailable.new(message)
        when "internal"
          Internal.new(message)
        else
          Error.new(message)
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
