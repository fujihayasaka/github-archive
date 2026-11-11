# typed: true
# frozen_string_literal: true

require "react_payload"

class Orgs::CopilotInsights::Controller < Orgs::Controller
  include ApplicationController::VerifiedFetchDependency
  include ::CopilotInsightsUsage::Shared

  before_action :login_required
  before_action :organization_read_required
  before_action :enforce_copilot_insights_allowed
  before_action :canonicalize_query_params

  sig { returns(T.nilable(String)) }
  def self.react_bundle_name
    "copilot-insights-usage"
  end

  sig { void }
  def show
    record_analytics_event(category: copilot_analytics_category, label: "org_id:#{this_organization.id}")
    respond_with_react(
      payload: copilot_insights_payload(metrics_key: copilot_metrics_key),
      title: copilot_page_title,
      page_data: { selected_link: :insights },
    )
  end

  private

  # @abstract Override in subclass to provide the MetricsKey enum value
  sig { returns(MetricsKey) }
  def copilot_metrics_key
    raise NotImplementedError, "Subclass must implement copilot_metrics_key"
  end

  # @abstract Override in subclass to provide the page title
  sig { returns(String) }
  def copilot_page_title
    raise NotImplementedError, "Subclass must implement copilot_page_title"
  end

  # @abstract Override in subclass to provide the analytics event category
  sig { returns(String) }
  def copilot_analytics_category
    raise NotImplementedError, "Subclass must implement copilot_analytics_category"
  end

  sig { void }
  def enforce_copilot_insights_allowed
    render_404 unless permissions_object.copilot_insights_org_dashboard_accessible?
  end

  sig { returns(CopilotInsightsPermissions::PermissionCheck) }
  memoize def permissions_object
    CopilotInsightsPermissions::PermissionCheck.new(organization: this_organization, user: current_user)
  end

  sig { returns(Copilot::Organization) }
  memoize def copilot_organization
    Copilot::Organization.new(this_organization)
  end

  sig { returns(T.nilable(Copilot::Business)) }
  memoize def copilot_business
    return unless this_organization.business

    Copilot::Business.new(this_organization.business)
  end

  # Sidenav props passed to React partial
  sig { returns(T::Hash[Symbol, T.untyped]) }
  def sidenav
    {
      selectedKey: sidenav_selected_key,
      showDependencies: this_organization.dependency_insights_visible?(current_user),
      showActionsUsageMetrics: this_organization.actions_usage_metrics_enabled?(current_user),
      showApi: this_organization.api_insights_enabled?(current_user),
      showCopilotUsage: permissions_object.copilot_insights_org_dashboard_accessible?,
      showCopilotCodeGeneration: permissions_object.copilot_insights_org_dashboard_accessible?,
      showCopilotImpact: permissions_object.copilot_insights_impact_dashboard_accessible?,
      urls: sidenav_urls
    }
  end

  sig { returns(String) }
  def sidenav_selected_key
    raise NotImplementedError, "Subclass must implement"
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def sidenav_urls
    paths = {
      actions_performance_metrics: actions_performance_metrics_path(this_organization),
      actions_usage_metrics: actions_usage_metrics_path(this_organization),
      dependency_insights: packages_dashboard_org_insights_path(this_organization),
      api: api_org_insights_path(this_organization),
    }

    if permissions_object.copilot_insights_org_dashboard_accessible?
      paths[:copilot_metrics_usage] = copilot_insights_usage_path(this_organization)
      paths[:copilot_metrics_code_generation] = copilot_insights_code_generation_path(this_organization)
    end

    if permissions_object.copilot_insights_impact_dashboard_accessible?
      paths[:copilot_metrics_impact] = copilot_insights_impact_path(this_organization)
    end

    paths
  end

  sig { returns(String) }
  def copilot_license_management_link
    if copilot_organization.copilot_billable? || copilot_organization.has_trial?
      "/organizations/#{this_organization.display_login}/settings/copilot/seat_management"
    else
      "/organizations/#{this_organization.display_login}/settings/copilot/enable"
    end
  end

  sig { returns(String) }
  def ai_controls_link
    "/organizations/#{this_organization.display_login}/settings/copilot/policies"
  end

  sig { returns(String) }
  def enterprise_ai_controls_link
    return ai_controls_link unless this_organization.business

    if copilot_business&.copilot_standalone?
      settings_copilot_enterprise_path(this_organization.business)
    else
      copilot_enterprise_ai_controls_enterprise_path(this_organization.business)
    end
  end

  sig { returns(T::Boolean) }
  def insights_opted_in?
    copilot_organization.insights_enabled?
  end

  sig { returns(T::Boolean) }
  def copilot_disabled?
    !copilot_organization.copilot_enabled?
  end

  sig { returns(T::Boolean) }
  def can_manage_copilot_licenses?
    this_organization.adminable_by?(current_user) ||
      this_organization.resources.organization_copilot_seat_management.writable_by?(current_user)
  end

  sig { returns(T::Boolean) }
  def can_manage_ai_controls?
    return can_manage_copilot_licenses? if enterprise_policy_unset?

    can_manage_enterprise_ai_controls?
  end

  sig { returns(String) }
  def resolved_ai_controls_link
    return ai_controls_link if enterprise_policy_unset?

    enterprise_ai_controls_link
  end

  sig { returns(T::Boolean) }
  def enterprise_policy_unset?
    return true unless copilot_business

    T.must(copilot_business).insights_no_policy?
  end

  sig { returns(T::Boolean) }
  def can_manage_enterprise_ai_controls?
    this_organization.business&.actor_can_write_enterprise_ai_controls?(current_user) || false
  end

  # Maps a MetricsKey to the org-specific React route ID.
  sig { params(metrics_key: MetricsKey).returns(String) }
  def metrics_key_route_id(metrics_key)
    case metrics_key
    when MetricsKey::UsageMetrics then "orgCopilotUsageRoute"
    when MetricsKey::CodeGenerationMetrics then "orgCopilotCodeGenerationRoute"
    when MetricsKey::ImpactMetrics then "orgCopilotImpactRoute"
    else T.absurd(metrics_key)
    end
  end

  sig { returns(T.untyped) }
  def fetch_dashboard_results
    spark = FeatureFlag.vexi.enabled?(SPARK_USAGE_REPORT_FLAG, this_organization, default: false)
    cus = cus_dashboard_enabled?(this_organization)
    fetch_copilot_dashboard_results(organization: this_organization, days: days, spark: spark, cus: cus)
  end

  sig { params(metrics_key: MetricsKey).returns(CopilotInsights::Payload) }
  def copilot_insights_payload(metrics_key:)
    results = fetch_dashboard_results
    metrics = extract_copilot_metrics(metrics_key, results)
    page_type = metrics_key_to_page_type(metrics_key)
    display_flags = {
      blankslate: results.display_flags.fetch(:blankslate, false),
      error: results.display_flags.fetch(:error, false),
      no_matching_results: results.display_flags.fetch(:no_matching_results, false),
      usage_disclaimer: results.display_flags.fetch(:usage_disclaimer, false),
      code_generation_disclaimer: results.display_flags.fetch(:code_generation_disclaimer, false),
    }

    CopilotInsights::Payload.new(
      route_id: metrics_key_route_id(metrics_key),
      metrics_key: metrics_key,
      metrics: metrics,
      display_flags: display_flags,
      sidenav: sidenav,
      slug: this_organization.display_login,
      org_name: this_organization.name,
      org_id: this_organization.id,
      copilot_license_management_link: copilot_license_management_link,
      ai_controls_link: resolved_ai_controls_link,
      insights_opted_in: insights_opted_in?,
      can_manage_ai_controls: can_manage_ai_controls?,
      copilot_disabled: copilot_disabled?,
      can_manage_copilot_licenses: can_manage_copilot_licenses?,
      export_files_url: copilot_insights_export_path(this_organization, page_type: page_type),
      canonical_query_params: @canonical_params,
      imported_data_filename: imported_data_filename,
    )
  end
end
