# typed: strict
# frozen_string_literal: true

require "react_payload"

class Businesses::CopilotInsightsUsageController < Businesses::CopilotInsightsBaseController

  before_action :copilot_insights_usage_required

  sig { void }
  def show
    result = fetch_dashboard_results
    metrics = get_metrics_from_result(result)
    display_blankslate = result.display_blankslate
    display_error = result.display_error

    record_analytics_event

    render_insights_response(metrics, display_blankslate, display_error)
  end

  private

  sig { params(result: T.untyped).returns(T.untyped) }
  def get_metrics_from_result(result)
    result.usage_metrics
  end

  sig { void }
  def record_analytics_event
    analytics_event(
      category: "copilot_metrics_usage_enterprise_dashboard",
      action: "show",
      label: "business_id:#{this_business.id}"
    )
  end

  sig { params(metrics: T.untyped, display_blankslate: T::Boolean, display_error: T::Boolean).returns(T.untyped) }
  def build_payload(metrics, display_blankslate, display_error)
    {
      copilotUsageRoute: {
        copilotLicenseManagementLink: settings_copilot_first_run_flow_cta_enterprise_path(current_business),
        exportFilesUrl: copilot_insights_export_files_enterprise_insights_path(current_business, page_type: "usage"),
        displayBlankslate: display_blankslate,
        displayError: display_error,
        usageMetrics: metrics,
        slug: current_business&.slug,
        businessId: current_business&.id,
        canonicalQueryParams: @canonical_params,
      }
    }
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
end
