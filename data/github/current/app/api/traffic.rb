# typed: true
# frozen_string_literal: true

require "octolytics/pond"

class Api::Traffic < Api::App
  VALID_TIME_AGGREGATIONS = %w[day week]

  before do
    deliver_error!(404) unless GitHub.traffic_graphs_enabled?
  end

  error Octolytics::ServerError, Api::Serializer::InvalidTimestampError do
    Failbot.report(env["sinatra.error"])
    deliver_error! 503, message: "The Traffic API is temporarily unavailable"
  end

  get "/repositories/:repository_id/traffic/popular/referrers", operation_id: "repos/get-top-referrers" do
    repo = find_repo!
    set_error_message(repo)
    control_access :repo_traffic, resource: repo, forbid: repo.public?, allow_integrations: true, allow_user_via_granular_actor: true

    # No-op request to new service for load testing
    GitHub.hydro_aggregation_api_client.repo_top_referrers(repo_id: repo.id, from: 2.weeks.ago)

    data = pond_client.referrers(repo.id).data["data"].first(10)
    deliver :traffic_referrers_hash, data, repo: repo
  end

  get "/repositories/:repository_id/traffic/popular/paths", operation_id: "repos/get-top-paths" do
    repo = find_repo!
    set_error_message(repo)
    control_access :repo_traffic, resource: repo, forbid: repo.public?, allow_integrations: true, allow_user_via_granular_actor: true

    # No-op request to new service for load testing
    GitHub.hydro_aggregation_api_client.repo_top_content(repo_id: repo.id, from: 2.weeks.ago)

    data = pond_client.content(repo.id).data["data"].first(10)
    deliver :traffic_contents_hash, data, repo: repo
  end

  get "/repositories/:repository_id/traffic/clones", operation_id: "repos/get-clones" do
    repo = find_repo!
    set_error_message(repo)
    control_access :repo_traffic, resource: repo, forbid: repo.public?, allow_integrations: true, allow_user_via_granular_actor: true

    period = get_period(params, "get-repository-clones")

    # No-op request to new service for load testing
    GitHub.hydro_aggregation_api_client.repo_clones(repo_id: repo.id, from: 2.weeks.ago, granularity: get_granularity(period))

    data = pond_client.counts(repo.id, "clone", period).data["data"]
    deliver :traffic_clones_hash, data, repo: repo
  end

  get "/repositories/:repository_id/traffic/views", operation_id: "repos/get-views" do
    repo = find_repo!
    set_error_message(repo)
    control_access :repo_traffic, resource: repo, forbid: repo.public?, allow_integrations: true, allow_user_via_granular_actor: true

    period = get_period(params, "get-page-views")

    # No-op request to new service for load testing
    GitHub.hydro_aggregation_api_client.repo_page_views(repo_id: repo.id, from: 2.weeks.ago, granularity: get_granularity(period))

    data = pond_client.counts(repo.id, "view", period).data["data"]
    deliver :traffic_views_hash, data, repo: repo
  end

  private

  def pond_client
    GitHub.pond_client
  end

  def set_error_message(repo)
    if access_allowed?(:get_repo, resource: repo, allow_integrations: true, allow_user_via_granular_actor: true)
      set_forbidden_message "Must have push access to repository"
    end
  end

  def get_period(params, endpoint_name)
    period = params[:per].presence || "day"
    unless period.in?(VALID_TIME_AGGREGATIONS)
      deliver_error! 422,
      message: "Invalid time aggregation",
      documentation_url: "/rest/reference/repos##{endpoint_name}"
    end
    period
  end

  def get_granularity(period)
    period == "day" ? :DAY : :WEEK
  end
end
