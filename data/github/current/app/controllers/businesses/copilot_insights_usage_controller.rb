# typed: strict
# frozen_string_literal: true

require "react_payload"

class Businesses::CopilotInsightsUsageController < Businesses::CopilotInsightsBaseController
  before_action :copilot_insights_usage_required

  sig { returns(T.nilable(String)) }
  def self.react_bundle_name
    "copilot-insights-usage"
  end

  sig { void }
  def show
    route_id = "copilotUsageRoute"
    metrics_key = :usageMetrics
    license_management_link = settings_copilot_first_run_flow_cta_enterprise_path(current_business)
    opted_in = insights_opted_in?

    record_analytics_event
    add_client_feature_flag([:copilot_insights_public_preview], entity: current_business)
    render_insights_response(route_id:, metrics_key:, license_management_link:, opted_in:)
  end

  private

  sig { void }
  def record_analytics_event
    analytics_event(
      category: "copilot_metrics_usage_enterprise_dashboard",
      action: "show",
      label: "business_id:#{this_business.id}"
    )
  end

  sig { returns(String) }
  def page_title
    "Copilot IDE usage"
  end

  sig { returns(Symbol) }
  def sidebar_link
    :copilot_insights
  end

  sig { void }
  def copilot_insights_usage_required
    return if copilot_insights_usage_available?(business: current_business, user: current_user)

    render_404
  end

  sig { returns(T::Boolean) }
  def insights_opted_in?
    copilot_insights_usage_feature_opted_in?(business: current_business, user: current_user)
  end
end
