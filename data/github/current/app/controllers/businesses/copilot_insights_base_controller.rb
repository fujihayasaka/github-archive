# typed: strict
# frozen_string_literal: true

require "react_payload"

class Businesses::CopilotInsightsBaseController < Businesses::BusinessController
  include ::CopilotInsightsUsage::Shared
  include Businesses::CopilotShared

  depends_on_clusters ApplicationRecord::Mysql1, ApplicationRecord::Configurations, ApplicationRecord::IamAbilities, ApplicationRecord::Copilot

  before_action :login_required
  before_action :dotcom_required
  before_action :canonicalize_query_params
  before_action :enforce_copilot_insights_allowed

  sig { returns(T.nilable(String)) }
  def self.react_bundle_name
    "copilot-insights-shared"
  end

  sig { void }
  def show
    record_analytics_event(category: copilot_analytics_category, label: "business_id:#{this_business.id}")
    respond_with_react(
      payload: copilot_insights_payload(metrics_key: copilot_metrics_key),
      title: copilot_page_title,
      page_data: {
        sidebar: :insights,
        selected_link: sidebar_link
      },
      layout: "react_business",
    )
  end

  private

  # @abstract Override in subclass to provide the MetricsKey enum value
  sig { overridable.returns(MetricsKey) }
  def copilot_metrics_key
    raise NotImplementedError, "Subclass must implement copilot_metrics_key"
  end

  # @abstract Override in subclass to provide the page title
  sig { overridable.returns(String) }
  def copilot_page_title
    raise NotImplementedError, "Subclass must implement copilot_page_title"
  end

  # @abstract Override in subclass to provide the analytics event category
  sig { overridable.returns(String) }
  def copilot_analytics_category
    raise NotImplementedError, "Subclass must implement copilot_analytics_category"
  end

  # @abstract Override in subclass to provide the sidebar link identifier
  sig { overridable.returns(Symbol) }
  def sidebar_link
    raise NotImplementedError, "Subclass must implement sidebar_link"
  end

  # @abstract Override in subclass to check feature availability for this page
  sig { overridable.returns(T::Boolean) }
  def copilot_insights_feature_available?
    raise NotImplementedError, "Subclass must implement copilot_insights_feature_available?"
  end

  sig { void }
  def enforce_copilot_insights_allowed
    return if copilot_insights_feature_available?

    render_404
  end

  sig { returns(CopilotInsightsPermissions::PermissionCheck) }
  memoize def permissions_object
    CopilotInsightsPermissions::PermissionCheck.new(business: current_business, user: current_user)
  end

  sig { returns(T::Boolean) }
  def insights_opted_in?
    permissions_object.copilot_insights_usage_feature_opted_in?
  end

  sig { returns(T.untyped) }
  def fetch_dashboard_results
    spark = FeatureFlag.vexi.enabled?(SPARK_USAGE_REPORT_FLAG, current_business, default: false)
    cus = cus_dashboard_enabled?(current_business)
    fetch_copilot_dashboard_results(business: current_business, days: days, spark: spark, cus: cus)
  end

  # Maps a MetricsKey to the enterprise-specific React route ID.
  sig { params(metrics_key: MetricsKey).returns(String) }
  def metrics_key_route_id(metrics_key)
    case metrics_key
    when MetricsKey::UsageMetrics then "copilotUsageRoute"
    when MetricsKey::CodeGenerationMetrics then "copilotCodeGenerationRoute"
    when MetricsKey::ImpactMetrics then "copilotImpactRoute"
    else T.absurd(metrics_key)
    end
  end

  sig { returns(String) }
  def get_ai_controls_link
    if standalone_business?
      settings_copilot_enterprise_path(current_business)
    else
      copilot_enterprise_ai_controls_enterprise_path(current_business)
    end
  end

  sig { returns(String) }
  def get_license_management_link
    # access to the license management link is only for users with business access
    return "" unless business_access?

    enterprise_licensing_path(current_business)
  end

  sig { returns(T::Boolean) }
  def copilot_disabled?
    !copilot_business.copilot_seat_count.positive?
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
      slug: current_business&.slug,
      business_id: current_business&.id,
      export_files_url: copilot_insights_export_files_enterprise_insights_path(current_business, page_type: page_type),
      copilot_license_management_link: get_license_management_link,
      ai_controls_link: get_ai_controls_link,
      canonical_query_params: @canonical_params,
      imported_data_filename: imported_data_filename,
      insights_opted_in: insights_opted_in?,
      can_manage_ai_controls: !!current_business&.actor_can_write_enterprise_ai_controls?(current_user),
      copilot_disabled: copilot_disabled?,
    )
  end
end
