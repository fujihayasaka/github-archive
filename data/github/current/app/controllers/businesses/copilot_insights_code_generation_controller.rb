# typed: strict
# frozen_string_literal: true

require "react_payload"

class Businesses::CopilotInsightsCodeGenerationController < Businesses::CopilotInsightsBaseController
  before_action :copilot_insights_code_generation_required

  sig { returns(T.nilable(String)) }
  def self.react_bundle_name
    "copilot-insights-code-generation"
  end

  sig { void }
  def show
    route_id = "copilotCodeGenerationRoute"
    metrics_key = :codeGenerationMetrics
    opted_in = insights_opted_in?

    record_analytics_event
    render_insights_response(route_id:, metrics_key:, license_management_link: nil, opted_in:)
  end

  private

  sig { void }
  def record_analytics_event
    analytics_event(
      category: "copilot_metrics_code_generation_enterprise_dashboard",
      action: "show",
      label: "business_id:#{this_business.id}"
    )
  end

  sig { returns(String) }
  def page_title
    "IDE code generation"
  end

  sig { returns(Symbol) }
  def sidebar_link
    :copilot_insights_code_generation
  end

  sig { void }
  def copilot_insights_code_generation_required
    return if copilot_insights_code_generation_available?(business: current_business, user: current_user)

    render_404
  end

  sig { returns(T::Boolean) }
  def insights_opted_in?
    copilot_insights_usage_feature_opted_in?(business: current_business, user: current_user)
  end
end
