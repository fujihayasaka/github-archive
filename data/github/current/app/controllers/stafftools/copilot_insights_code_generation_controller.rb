# typed: true
# frozen_string_literal: true

class Stafftools::CopilotInsightsCodeGenerationController < Stafftools::CopilotInsightsBaseController
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
    "copilot-insights-code-generation"
  end

  private

  sig { override.returns(String) }
  def copilot_insights_route_id = "stafftoolsUserCopilotCodeGenerationRoute"

  sig { override.returns(CopilotInsightsUsage::Shared::MetricsKey) }
  def copilot_insights_metrics_key = MetricsKey::CodeGenerationMetrics

  sig { override.returns(String) }
  def copilot_insights_title = "Copilot Code Generation Metrics - Stafftools"
end
