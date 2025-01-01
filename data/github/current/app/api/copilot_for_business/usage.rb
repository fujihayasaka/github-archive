# typed: true
# frozen_string_literal: true

class Api::CopilotForBusiness::Usage < Api::App
  include FeatureFlagHelper
  include ReceiveSchemaWithOpenApi

  DEFAULT_PER_PAGE = 28

  #### TEAM USAGE ENDPOINT ###
  get "/organizations/:organization_id/team/:team_id/copilot/usage", operation_id: "copilot/usage-metrics-for-team" do
    team = find_team!(param_name: :team_id, org_param_name: :organization_id)
    org = team.organization

    ensure_endpoint_enabled(org)

    # global endpoint gate - to be globally enabled upon feature flag rollout and then removed
    deliver_error!(404, documentation_url: "#{GitHub::Config::DOCS_BASE_URL}/rest") unless org.feature_enabled?(:enable_usage_metrics_team_endpoint) || org.business&.feature_enabled?(:enable_usage_metrics_team_endpoint)

    control_access :copilot_org_usage_metrics,
      resource: org,
      allow_user_via_granular_actor: true,
      allow_integrations: true,
      enforce_oauth_app_policy: true

    receive_with_openapi

    usage_metrics = usage_metrics_list_for_entity(team)

    paginated_usage_metrics = paginate_usage_metrics(usage_metrics)

    deliver_raw(paginated_usage_metrics)
  end

  #### ORGANIZATION USAGE ENDPOINT ###
  get "/organizations/:organization_id/copilot/usage", operation_id: "copilot/usage-metrics-for-org" do
    @route_owner = "@github/heart-services"

    org = find_org!

    ensure_endpoint_enabled(org)

    control_access :copilot_org_usage_metrics,
      resource: org,
      allow_user_via_granular_actor: true,
      allow_integrations: true,
      enforce_oauth_app_policy: true

    receive_with_openapi

    usage_metrics = usage_metrics_list_for_entity(org)

    paginated_usage_metrics = paginate_usage_metrics(usage_metrics)

    deliver_raw(paginated_usage_metrics)
  end

  #### ENTERPRISE USAGE ENDPOINT ###
  get "/enterprises/:enterprise_id/copilot/usage", operation_id: "copilot/usage-metrics-for-enterprise" do
    @route_owner = "@github/heart-services"

    enterprise = find_enterprise!

    ensure_endpoint_enabled(enterprise)

    control_access :copilot_enterprise_usage_metrics,
      resource: enterprise,
      allow_user_via_granular_actor: false,
      allow_integrations: false

    receive_with_openapi

    usage_metrics = usage_metrics_list_for_entity(enterprise)

    paginated_usage_metrics = paginate_usage_metrics(usage_metrics)

    deliver_raw(paginated_usage_metrics)
  end

  #### ENTERPRISE TEAM USAGE ENDPOINT ###
  get "/enterprises/:enterprise_id/team/:team_id/copilot/usage", operation_id: "copilot/usage-metrics-for-enterprise-team" do
    @route_owner = "@github/heart-services"

    enterprise_team = find_enterprise_team!
    enterprise = enterprise_team.business

    # global endpoint gate - to be globally enabled upon feature flag rollout and then removed
    deliver_error!(404, documentation_url: "#{GitHub::Config::DOCS_BASE_URL}/rest") unless enterprise.feature_enabled?(:enable_usage_metrics_ent_team_endpoint)

    ensure_endpoint_enabled(enterprise)

    control_access :copilot_enterprise_usage_metrics,
      resource: enterprise,
      allow_user_via_granular_actor: false,
      allow_integrations: false

    receive_with_openapi

    usage_metrics = usage_metrics_list_for_entity(enterprise_team)

    paginated_usage_metrics = paginate_usage_metrics(usage_metrics)

    deliver_raw(paginated_usage_metrics)
  end

  def ensure_endpoint_enabled(entity)
    # TODO: we will eventually want this enabled in proxima
    disabled = GitHub.enterprise? || GitHub.multi_tenant_enterprise?

    ensure_not_feature_flag_blocked(entity)

    deliver_error!(404) if disabled
  end

  # emergency lever, add orgs/enterprises to the block_copilot_usage_metrics_api flag to disable the usage metrics API completely
  # TODO: return a specific error code/message when we do this?
  def ensure_not_feature_flag_blocked(entity)
    blocked = entity.feature_enabled?(:block_copilot_usage_metrics_api)
    blocked ||= entity.business&.feature_enabled?(:block_copilot_usage_metrics_api) if entity.is_a?(::Organization) || entity.is_a?(::EnterpriseTeam)

    deliver_error!(404, documentation_url: "#{GitHub::Config::DOCS_BASE_URL}/rest") if blocked
  end

  def date_params
    {
      since_date: params[:since].present? ? parse_time!(params[:since]).to_date : nil,
      until_date: params[:until].present? ? parse_time!(params[:until]).to_date : nil
    }
  end

  def usage_metrics_list_for_entity(entity)
    dates = date_params
    since_date = dates[:since_date]
    until_date = dates[:until_date]

    if since_date && since_date < 28.days.ago
      deliver_error!(422, message: "Value of since parameter cannot be prior to 28 days ago.")
    end

    if since_date && until_date && until_date < since_date
      deliver_error!(422, message: "Until date cannot be prior to since date.")
    end

    usage_metrics = case entity
    when Organization
      Copilot::Metrics::UsageMetrics.new(organization: entity)
    when Business
      Copilot::Metrics::UsageMetrics.new(business: entity)
    when Team
      Copilot::Metrics::UsageMetrics.new(team: entity)
    when EnterpriseTeam
      Copilot::Metrics::UsageMetrics.new(enterprise_team: entity)
    else
      return []
    end

    usage_metrics.usage_details(since_date, until_date)
  end

  def paginate_usage_metrics(usage_metrics_for_entity)
    total_days = usage_metrics_for_entity.count
    paginator.collection_size = total_days
    add_links(total_days)

    paginate_rel(usage_metrics_for_entity)
  end

  def add_links(collection_size)
    last_page = (collection_size / per_page.to_f).ceil
    if collection_size > per_page
      @links.add_current({ page: last_page }, rel: "last") if current_page != last_page
      @links.add_current({ page: current_page + 1 }, rel: "next") if current_page < last_page
      if current_page && current_page > 1
        @links.add_current({ page: 1 }, rel: "first")
        prev_page = (current_page <= last_page) ? current_page - 1 : 1
        @links.add_current({ page: prev_page }, rel: "prev")
      end
    end
  end
end
