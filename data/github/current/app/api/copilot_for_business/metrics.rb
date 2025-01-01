# typed: true
# frozen_string_literal: true

class Api::CopilotForBusiness::Metrics < Api::App
  include FeatureFlagHelper
  include ReceiveSchemaWithOpenApi

  DEFAULT_PER_PAGE = 28

  #### ORGANIZATION TEAM METRICS ENDPOINT ###
  get "/organizations/:organization_id/team/:team_id/copilot/metrics", operation_id: "copilot/copilot-metrics-for-team" do
    team = find_team!(param_name: :team_id, org_param_name: :organization_id)
    org = team.organization

    # killswitch for this endpoint
    deliver_error!(404, documentation_url: "#{GitHub::Config::DOCS_BASE_URL}/rest") if flag_enabled_for_entity_or_parent?(org, :disable_copilot_metrics_api_v2_org_teams)

    ensure_endpoint_enabled!(org)

    control_access :copilot_org_usage_metrics,
      resource: org,
      allow_user_via_granular_actor: true,
      allow_integrations: true,
      enforce_oauth_app_policy: true,
      forbid: true,
      forbid_message: Copilot::ORG_OR_ENTERPRISE_ADMIN_FORBID_MESSAGE

    receive_with_openapi

    usage_metrics = usage_metrics_list_for_entity!(team)

    paginated_usage_metrics = paginate_usage_metrics(usage_metrics)

    deliver_raw(paginated_usage_metrics)
  end

  #### ORGANIZATION METRICS ENDPOINT ###
  get "/organizations/:organization_id/copilot/metrics", operation_id: "copilot/copilot-metrics-for-organization" do
    @route_owner = "@github/heart-services"

    org = find_org!

    # killswitch for this endpoint
    deliver_error!(404, documentation_url: "#{GitHub::Config::DOCS_BASE_URL}/rest") if flag_enabled_for_entity_or_parent?(org, :disable_copilot_metrics_api_v2_orgs)

    ensure_endpoint_enabled!(org)

    control_access :copilot_org_usage_metrics,
      resource: org,
      allow_user_via_granular_actor: true,
      allow_integrations: true,
      enforce_oauth_app_policy: true,
      forbid: true,
      forbid_message: Copilot::ORG_OR_ENTERPRISE_ADMIN_FORBID_MESSAGE

    receive_with_openapi

    usage_metrics = usage_metrics_list_for_entity!(org)

    paginated_usage_metrics = paginate_usage_metrics(usage_metrics)

    deliver_raw(paginated_usage_metrics)
  end

  #### ENTERPRISE METRICS ENDPOINT ###
  get "/enterprises/:enterprise_id/copilot/metrics", operation_id: "copilot/copilot-metrics-for-enterprise" do
    @route_owner = "@github/heart-services"

    enterprise = find_enterprise!

    # killswitch for this endpoint
    deliver_error!(404, documentation_url: "#{GitHub::Config::DOCS_BASE_URL}/rest") if flag_enabled_for_entity_or_parent?(enterprise, :disable_copilot_metrics_api_v2_enterprises)

    ensure_endpoint_enabled!(enterprise)

    control_access :copilot_enterprise_usage_metrics,
      resource: enterprise,
      allow_user_via_granular_actor: false,
      allow_integrations: false,
      forbid: true,
      forbid_message: Copilot::ENTERPRISE_ADMIN_FORBID_MESSAGE

    receive_with_openapi

    usage_metrics = usage_metrics_list_for_entity!(enterprise)

    paginated_usage_metrics = paginate_usage_metrics(usage_metrics)

    deliver_raw(paginated_usage_metrics)
  end

  #### ENTERPRISE TEAM METRICS ENDPOINT ###
  get "/enterprises/:enterprise_id/team/:team_id/copilot/metrics", operation_id: "copilot/copilot-metrics-for-enterprise-team" do
    @route_owner = "@github/heart-services"

    enterprise_team = find_enterprise_team!
    enterprise = enterprise_team.business

    # killswitch for this endpoint
    deliver_error!(404, documentation_url: "#{GitHub::Config::DOCS_BASE_URL}/rest") if flag_enabled_for_entity_or_parent?(enterprise, :disable_copilot_metrics_api_v2_enterprise_teams)

    ensure_endpoint_enabled!(enterprise)

    control_access :copilot_enterprise_usage_metrics,
      resource: enterprise,
      allow_user_via_granular_actor: false,
      allow_integrations: false,
      forbid: true,
      forbid_message: Copilot::ENTERPRISE_ADMIN_FORBID_MESSAGE

    receive_with_openapi

    usage_metrics = usage_metrics_list_for_entity!(enterprise_team)

    paginated_usage_metrics = paginate_usage_metrics(usage_metrics)

    deliver_raw(paginated_usage_metrics)
  end

  def ensure_endpoint_enabled!(entity)
    # TODO: we will eventually want this enabled in proxima
    disabled = GitHub.enterprise? || GitHub.multi_tenant_enterprise?

    ensure_not_feature_flag_blocked!(entity)
    ensure_policy_enabled!(entity)

    deliver_error!(404, documentation_url: "#{GitHub::Config::DOCS_BASE_URL}/rest") if disabled
  end

  def ensure_policy_enabled!(entity)
    copilot_entity = case entity
    when ::Organization
      Copilot::Organization.new(entity)
    when ::Business
      Copilot::Business.new(entity)
    else
      raise "What? The entity is not an organization or business"
    end

    enabled = copilot_entity.telemetry_aggregation_enabled?

    unless enabled
      entity_name = entity.is_a?(::Organization) ? "organization" : "enterprise"
      deliver_error!(422,
        message: "Your #{entity_name} has disabled Copilot Metrics API access. Enable it in GitHub settings to access this endpoint."
      )
    end
  end

  # emergency lever, add orgs/enterprises to the block_copilot_usage_metrics_api flag to disable the metrics API completely
  # TODO: return a specific error code/message when we do this?
  def ensure_not_feature_flag_blocked!(entity)
    blocked = flag_enabled_for_entity_or_parent?(entity, :block_copilot_usage_metrics_api)

    deliver_error!(404, documentation_url: "#{GitHub::Config::DOCS_BASE_URL}/rest") if blocked
  end

  def date_params
    {
      since_date: params[:since].present? ? parse_time!(params[:since]).to_date : nil,
      until_date: params[:until].present? ? parse_time!(params[:until]).to_date : nil
    }
  end

  # checks whether the feature flag is enabled for the entity itself if it's a business or an org without a business
  # or if it's enabled for the entity's parent if it's an org with a business or an enterprise team
  def flag_enabled_for_entity_or_parent?(entity, flag_name)
    return true if GitHub.flipper[flag_name].enabled?
    enabled = entity.feature_enabled?(flag_name)
    enabled ||= entity.business&.feature_enabled?(flag_name) if entity.is_a?(::Organization)

    enabled
  end

  def usage_metrics_list_for_entity!(entity)
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
      Copilot::Metrics::CopilotMetrics.new(organization: entity)
    when Business
      Copilot::Metrics::CopilotMetrics.new(business: entity)
    when Team
      Copilot::Metrics::CopilotMetrics.new(team: entity)
    when EnterpriseTeam
      Copilot::Metrics::CopilotMetrics.new(enterprise_team: entity)
    else
      return []
    end

    usage_metrics.payload(since_date, until_date)
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
