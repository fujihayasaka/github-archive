# typed: true
# frozen_string_literal: true

class Api::OrganizationApiInsights < Api::App

  get "/organizations/:organization_id/insights/api/summary-stats/users/:user_id", operation_id: "api-insights/get-summary-stats-by-user" do
    org = find_org!

    control_access :view_org_api_insights,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    run_stats_query!(org) do
      stats = ApiInsights::Stats::SummaryStats.new(org.id, min_timestamp, max_timestamp).with_user(user_id)
      stats.with_tenant_id(tenant_id) if GitHub.multi_tenant_enterprise?
      data = stats.get
      deliver :org_api_insights_summary_stats, data
    end
  end

  get "/organizations/:organization_id/insights/api/summary-stats/:actor_type/:actor_id", operation_id: "api-insights/get-summary-stats-by-actor" do
    org = find_org!

    control_access :view_org_api_insights,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    run_stats_query!(org) do
      stats = ApiInsights::Stats::SummaryStats.new(org.id, min_timestamp, max_timestamp)
      stats.with_tenant_id(tenant_id) if GitHub.multi_tenant_enterprise?
      stats = case actor_type
      when "installation"
        stats.with_installation(actor_id)
      when "oauth_app"
        stats.with_oauth_app(actor_id)
      when "classic_pat"
        stats.with_classic_pat(actor_id)
      when "fine_grained_pat"
        stats.with_fine_grained_pat(actor_id)
      when "github_app_user_to_server"
        stats.with_github_app_user_to_server(actor_id)
      else
        deliver_error! 422, message: "Invalid actor type"
      end
      data = stats.get
      deliver :org_api_insights_summary_stats, data
    end
  end

  get "/organizations/:organization_id/insights/api/summary-stats", operation_id: "api-insights/get-summary-stats" do

    org = find_org!

    control_access :view_org_api_insights,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    run_stats_query!(org) do
      stats = ApiInsights::Stats::SummaryStats.new(org.id, min_timestamp, max_timestamp)
      stats.with_tenant_id(tenant_id) if GitHub.multi_tenant_enterprise?
      data = stats.get
      deliver :org_api_insights_summary_stats, data
    end

  end

  get "/organizations/:organization_id/insights/api/time-stats/users/:user_id", operation_id: "api-insights/get-time-stats-by-user" do
    org = find_org!

    control_access :view_org_api_insights,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    run_stats_query!(org) do
      stats = ApiInsights::Stats::TimeStats.new(org.id, min_timestamp, max_timestamp, timestamp_increment)
        .with_user(user_id)
      stats.with_tenant_id(tenant_id) if GitHub.multi_tenant_enterprise?
      data = stats.get
      deliver :org_api_insights_time_stats, { stats: data }
    end
  end

  get "/organizations/:organization_id/insights/api/time-stats/:actor_type/:actor_id", operation_id: "api-insights/get-time-stats-by-actor" do
    org = find_org!

    control_access :view_org_api_insights,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    run_stats_query!(org) do
      stats = ApiInsights::Stats::TimeStats.new(org.id, min_timestamp, max_timestamp, timestamp_increment)
      stats.with_tenant_id(tenant_id) if GitHub.multi_tenant_enterprise?
      stats = case actor_type
      when "installation"
        stats.with_installation(actor_id)
      when "oauth_app"
        stats.with_oauth_app(actor_id)
      when "classic_pat"
        stats.with_classic_pat(actor_id)
      when "fine_grained_pat"
        stats.with_fine_grained_pat(actor_id)
      when "github_app_user_to_server"
        stats.with_github_app_user_to_server(actor_id)
      else
        deliver_error! 422, message: "Invalid actor type"
      end
      data = stats.get
      deliver :org_api_insights_time_stats, { stats: data }
    end
  end

  get "/organizations/:organization_id/insights/api/time-stats", operation_id: "api-insights/get-time-stats" do
    org = find_org!

    control_access :view_org_api_insights,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    run_stats_query!(org) do
      stats = ApiInsights::Stats::TimeStats.new(org.id, min_timestamp, max_timestamp, timestamp_increment)
      stats.with_tenant_id(tenant_id) if GitHub.multi_tenant_enterprise?
      data = stats.get
      deliver :org_api_insights_time_stats, { stats: data }
    end
  end

  get "/organizations/:organization_id/insights/api/subject-stats", operation_id: "api-insights/get-subject-stats" do
    org = find_org!

    control_access :view_org_api_insights,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    run_stats_query!(org) do

      stats = ApiInsights::Stats::SubjectStats.new(org.id, min_timestamp, max_timestamp)
        .with_paging(page: page, per_page: per_page)
        .with_sorting(sort_definitions)
      stats.with_subject_name_substring(subject_name_substring) if subject_name_substring.present?
      stats.with_tenant_id(tenant_id) if GitHub.multi_tenant_enterprise?
      data = stats.get

      deliver :org_api_insights_subject_stats, { stats: data.records, total_count: data.total_record_count }
    end
  end

  get "/organizations/:organization_id/insights/api/user-stats/:user_id", operation_id: "api-insights/get-user-stats" do
    org = find_org!

    control_access :view_org_api_insights,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    run_stats_query!(org) do
      stats = ApiInsights::Stats::UserStats.new(org.id, min_timestamp, max_timestamp, user_id)
        .with_paging(page: page, per_page: per_page)
        .with_sorting(sort_definitions)
      stats.with_actor_name_substring(actor_name_substring) if actor_name_substring.present?
      stats.with_tenant_id(tenant_id) if GitHub.multi_tenant_enterprise?
      data = stats.get

      deliver :org_api_insights_user_stats, { stats: data.records, total_count: data.total_record_count }
    end
  end

  get "/organizations/:organization_id/insights/api/route-stats/:actor_type/:actor_id", operation_id: "api-insights/get-route-stats-by-actor" do
    org = find_org!

    control_access :view_org_api_insights,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    run_stats_query!(org) do
      stats = ApiInsights::Stats::RouteStats.new(org.id, min_timestamp, max_timestamp)
      stats.with_api_route_substring(api_route_substring) if api_route_substring.present?
      stats.with_tenant_id(tenant_id) if GitHub.multi_tenant_enterprise?
      stats = case actor_type
      when "installation"
        stats.with_installation(actor_id)
      when "oauth_app"
        stats.with_oauth_app(actor_id)
      when "classic_pat"
        stats.with_classic_pat(actor_id)
      when "fine_grained_pat"
        stats.with_fine_grained_pat(actor_id)
      when "github_app_user_to_server"
        stats.with_github_app_user_to_server(actor_id)
      else
        deliver_error! 422, message: "Invalid actor type"
      end

      data = stats.with_paging(page: page, per_page: per_page)
        .with_sorting(sort_definitions)
        .get

      deliver :org_api_insights_route_stats, { stats: data.records, total_count: data.total_record_count }
    end
  end


  def run_stats_query!(org)

    receive_with_openapi

    yield

  rescue ApiInsights::Stats::Error => e
    deliver_error!(400, message: e.code.to_error_message)
  rescue Kusto::Error => e
    Failbot.report(e)
    raise
  end

  def min_timestamp
    time_param!("min_timestamp")
  end

  def max_timestamp
    if params["max_timestamp"].present?
      time_param!("max_timestamp")
    else
      Time.now.utc
    end
  end

  def user_id
    params["user_id"].to_i
  end

  def actor_id
    params["actor_id"].to_i
  end

  def actor_type
    params["actor_type"]
  end

  def actor_name_substring
    params["actor_name_substring"]
  end

  def api_route_substring
    params["api_route_substring"]
  end

  def subject_name_substring
    params["subject_name_substring"]
  end

  def timestamp_increment
    params["timestamp_increment"].to_s
  end

  def per_page
    pagination[:per_page] || 30
  end

  def page
    pagination[:page] || 1
  end

  def direction
    params[:direction] || "asc"
  end

  def sort(default)
    (params[:sort] || [default]).map { |s| select_sort_field(s) }
  end

  def select_sort_field(sort)
    case sort
    when "http_method"
      ApiInsights::Stats::Queries::SortField::HttpMethod
    when "api_route"
      ApiInsights::Stats::Queries::SortField::ApiRoute
    when "subject_name"
      ApiInsights::Stats::Queries::SortField::SubjectName
    when "total_request_count"
      ApiInsights::Stats::Queries::SortField::TotalRequestCount
    when "rate_limited_request_count"
      ApiInsights::Stats::Queries::SortField::RateLimitedRequestCount
    when "last_request_timestamp"
      ApiInsights::Stats::Queries::SortField::LastRequestTimestamp
    when "last_rate_limited_timestamp"
      ApiInsights::Stats::Queries::SortField::LastRateLimitedTimestamp
    end
  end

  def sort_definitions
    sort("total_request_count").map do |sort|
      ApiInsights::Stats::Queries::SortDefinition.new(sort, descending: descending?)
    end
  end

  def descending?
    direction == "desc"
  end

  def tenant_id
    GitHub::CurrentTenant.get.id
  end
end
