# typed: strict
# frozen_string_literal: true

require "react_payload"

class Businesses::CopilotInsightsCodeGenerationController < Businesses::CopilotInsightsBaseController
  before_action :copilot_insights_code_generation_required, if: ->(controller) do
    T.bind(self, Businesses::CopilotInsightsCodeGenerationController)
    # Skip export files permission check for site admins.
    # This allows them to download the export from stafftools
    controller.action_name == "export_files" ? !current_user.site_admin? : true
  end

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
    result.code_generation_metrics
  end

  sig { void }
  def record_analytics_event
    analytics_event(
      category: "copilot_metrics_code_generation_enterprise_dashboard",
      action: "show",
      label: "business_id:#{this_business.id}"
    )
  end

  sig { params(metrics: T.untyped, display_blankslate: T::Boolean, display_error: T::Boolean).returns(T.untyped) }
  def build_payload(metrics, display_blankslate, display_error)
    {
      copilotCodeGenerationRoute: {
        codeGenerationMetrics: metrics,
        exportFilesUrl: copilot_insights_export_files_enterprise_insights_path(current_business, page_type: "code_generation"),
        displayBlankslate: false, # update to display_blankslate when usagereport for loc is prod-ready
        displayError: false, # update to display_error when usagereport for loc is prod-ready
        slug: current_business&.slug,
        businessId: current_business&.id,
        canonicalQueryParams: @canonical_params,
      }
    }
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
end
