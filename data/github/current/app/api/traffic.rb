# typed: true
# frozen_string_literal: true

require "monolith-twirp-reposinsights-reposinsights"

class Api::Traffic < Api::App
  before do
    deliver_error!(404) unless GitHub.traffic_graphs_enabled?
  end

  VALID_TIME_AGGREGATIONS = %w[day week].freeze

  get "/repositories/:repository_id/traffic/popular/referrers", operation_id: "repos/get-top-referrers" do
    repo = find_repo!
    set_error_message(repo)
    control_access :repo_traffic, resource: repo, forbid: repo.public?, allow_integrations: true, allow_user_via_granular_actor: true

    deliver_correct_response(repo, :insights_client_traffic_referrers_hash)
  end

  get "/repositories/:repository_id/traffic/popular/paths", operation_id: "repos/get-top-paths" do
    repo = find_repo!
    set_error_message(repo)
    control_access :repo_traffic, resource: repo, forbid: repo.public?, allow_integrations: true, allow_user_via_granular_actor: true

    deliver_correct_response(repo, :insights_client_traffic_contents_hash)
  end

  get "/repositories/:repository_id/traffic/clones", operation_id: "repos/get-clones" do
    repo = find_repo!
    set_error_message(repo)
    control_access :repo_traffic, resource: repo, forbid: repo.public?, allow_integrations: true, allow_user_via_granular_actor: true

    period = get_period(params, "get-repository-clones")

    if period == "week"
      deliver_correct_response(repo, :insights_client_traffic_clones_weekly_hash)
    else
      deliver_correct_response(repo, :insights_client_traffic_clones_hash)
    end
  end

  get "/repositories/:repository_id/traffic/views", operation_id: "repos/get-views" do
    repo = find_repo!
    set_error_message(repo)
    control_access :repo_traffic, resource: repo, forbid: repo.public?, allow_integrations: true, allow_user_via_granular_actor: true

    period = get_period(params, "get-page-views")

    if period == "week"
      deliver_correct_response(repo, :insights_client_traffic_views_weekly_hash)
    else
      deliver_correct_response(repo, :insights_client_traffic_views_hash)
    end
  end

  private

  def set_error_message(repo)
    if access_allowed?(:get_repo, resource: repo, allow_integrations: true, allow_user_via_granular_actor: true)
      set_forbidden_message "Must have push access to repository"
    end
  end

  def deliver_correct_response(repo, serializer_name)
    response = RepositoryInsights.domain.traffic_for_repo(repo)
    if response&.dig(:traffic_data).present?
      deliver serializer_name, response
    else
      deliver_error! 503, message: "Traffic data is temporarily unavailable, please try again"
    end
  end

  def get_period(params, endpoint_name)
    period = params[:per].presence || "day"
    unless period.in?(VALID_TIME_AGGREGATIONS)
      deliver_error! 422, message: "Invalid time aggregation", documentation_url: "/rest/metrics/traffic##{endpoint_name}"
    end
    period
  end
end
