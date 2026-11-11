# typed: true
# frozen_string_literal: true

require "faraday"
require "monolith-twirp-reposinsights-reposinsights"

class RepositoryInsights::Client
  SERVICE_NAME = "repository_insights_github_client"
  class Error < StandardError; end
  class PermissionDenied < Error; end
  class Unavailable < Error; end
  class Internal < Error; end

  def initialize(http_adapter: self.class.default_http_adapter)
    @http_adapter = http_adapter
    @twirp_client = MonolithTwirp::ReposInsights::ReposInsights::V1::ReposInsightsAPIClient.new(http_adapter)
  end

  sig { params(repo_id: Integer).returns(MonolithTwirp::ReposInsights::ReposInsights::V1::GetRepoTrafficResponse) }
  def get_repo_traffic_data(repo_id)
    response = twirp_client.get_repo_traffic(MonolithTwirp::ReposInsights::ReposInsights::V1::GetRepoTrafficRequest.new(repository_id: repo_id))

    if response.error
      handle_error(response.error)
    end

    MonolithTwirp::ReposInsights::ReposInsights::V1::GetRepoTrafficResponse.decode(response.body)
  end

  sig { params(traffic_data: MonolithTwirp::ReposInsights::ReposInsights::V1::UpsertRepoTrafficRequest).returns(MonolithTwirp::ReposInsights::ReposInsights::V1::UpsertRepoTrafficResponse) }
  def upsert_repo_traffic_data(traffic_data)
    response = twirp_client.upsert_repo_traffic(traffic_data)

    if response.error
      handle_error(response.error)
    end

    MonolithTwirp::ReposInsights::ReposInsights::V1::UpsertRepoTrafficResponse.decode(response.body)
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
    case error.code
    when :permission_denied
      raise PermissionDenied, error.msg
    when :unavailable
      raise Unavailable, error.msg
    when :internal
      raise Internal, error.msg
    else
      raise Error, error.msg
    end
  end

  sig { returns(GitHub::FaradayClient::Internal) }
  attr_reader :http_adapter

  sig { returns(MonolithTwirp::ReposInsights::ReposInsights::V1::ReposInsightsAPIClient) }
  attr_reader :twirp_client
end
