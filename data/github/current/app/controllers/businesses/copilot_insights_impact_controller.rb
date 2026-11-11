# typed: strict
# frozen_string_literal: true

class Businesses::CopilotInsightsImpactController < Businesses::CopilotInsightsBaseController
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Copilot,
    only: [:show]

  # `show` action is inherited from Businesses::CopilotInsightsBaseController
  # and uses the below hooks to customize behavior for this page.

  sig { returns(T.nilable(String)) }
  def self.react_bundle_name
    "copilot-insights-impact"
  end

  private

  sig { override.returns(MetricsKey) }
  def copilot_metrics_key = MetricsKey::ImpactMetrics

  sig { override.returns(String) }
  def copilot_page_title = "Copilot impact metrics"

  sig { override.returns(String) }
  def copilot_analytics_category = "copilot_metrics_impact_enterprise_dashboard"

  sig { override.returns(Symbol) }
  def sidebar_link = :copilot_impact

  sig { override.returns(T::Boolean) }
  def copilot_insights_feature_available?
    return false unless permissions_object.copilot_insights_usage_feature_available?

    FeatureFlag.vexi.enabled?("glc_copilot_metrics_v2", current_user, current_business, default: false)
  end
end
