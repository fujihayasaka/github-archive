# typed: strict
# frozen_string_literal: true

require "react_payload"

class Businesses::CopilotInsightsBaseController < Businesses::BusinessController
  include CopilotInsightsPermissions
  include ::CopilotInsightsUsage::Params

  depends_on_clusters ApplicationRecord::Mysql1, ApplicationRecord::Configurations, ApplicationRecord::IamAbilities

  before_action :login_required
  before_action :dotcom_required
  before_action :canonicalize_query_params

  sig { returns(T.nilable(String)) }
  def self.react_bundle_name
    "copilot-insights-usage"
  end

  private

  sig { returns(T.untyped) }
  def fetch_dashboard_results
    ::CopilotInsightsUsage::DashboardService.call(business: current_business, days: days)
  end

  sig { params(metrics: T.untyped, display_blankslate: T::Boolean, display_error: T::Boolean).void }
  def render_insights_response(metrics, display_blankslate, display_error)
    respond_with_react(
      payload: build_payload(metrics, display_blankslate, display_error),
      title: page_title,
      page_data: {
        sidebar: :insights,
        selected_link: sidebar_link
      },
      layout: "react_business",
    )
  end

  sig { params(metrics: T.untyped, display_blankslate: T::Boolean, display_error: T::Boolean).returns(T.untyped) }
  def build_payload(metrics, display_blankslate, display_error)
    raise NotImplementedError, "Child controllers must implement build_payload"
  end

  sig { returns(String) }
  def page_title
    raise NotImplementedError, "Child controllers must implement page_title"
  end

  sig { returns(Symbol) }
  def sidebar_link
    raise NotImplementedError, "Child controllers must implement sidebar_link"
  end
end
