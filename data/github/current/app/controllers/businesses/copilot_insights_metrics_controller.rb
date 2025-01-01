# typed: strict
# frozen_string_literal: true

require "react_payload"

class Businesses::CopilotInsightsMetricsController < Businesses::BusinessController
  depends_on_clusters ApplicationRecord::Mysql1, ApplicationRecord::Configurations

  before_action :login_required
  before_action :dotcom_required
  before_action :copilot_insights_usage_details_required

  sig { returns(T.nilable(String)) }
  def self.react_bundle_name
    "copilot-insights-usage"
  end

  sig { void }
  def show
    respond_with_react(
      payload: nil,
      title: "Copilot Insights Metrics: Daily Active Users",
      page_data: {
        sidebar: :insights,
        selected_link: :copilot_insights_metrics_daily_active_users
      },
      layout: "react_business",
    )
  end

  private

  # TODO: Extract this method into shared permissions check method
  sig { void }
  def copilot_insights_usage_details_required
    return if current_user&.feature_flag_enabled_or_raise?(:copilot_insights_usage_details) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
    return if current_business&.feature_flag_enabled_or_raise?(:copilot_insights_usage_details) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage

    render_404
  end
end
