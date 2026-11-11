# typed: true
# frozen_string_literal: true

class Stafftools::CopilotInsightsUsageSparkController < Stafftools::CopilotInsightsBaseController
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Copilot,
    ApplicationRecord::Repositories,
    only: [:show]

  # `show` action is inherited from Stafftools::CopilotInsightsBaseController
  # and uses the below hooks to customize behavior for this page.

  sig { returns(T.nilable(String)) }
  def self.react_bundle_name
    "copilot-insights-usage"
  end

  private

  sig { override.returns(String) }
  def copilot_insights_route_id = "stafftoolsUserCopilotUsageSparkRoute"

  sig { override.returns(CopilotInsightsUsage::Shared::MetricsKey) }
  def copilot_insights_metrics_key = MetricsKey::UsageMetrics

  sig { override.returns(String) }
  def copilot_insights_title = "Copilot Usage Metrics (Spark) - Stafftools"

  sig { override.returns(T::Boolean) }
  def copilot_insights_spark? = true
end
