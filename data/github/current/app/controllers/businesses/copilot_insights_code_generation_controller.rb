# typed: strict
# frozen_string_literal: true

class Businesses::CopilotInsightsCodeGenerationController < Businesses::CopilotInsightsBaseController
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Copilot,
    only: [:show]

  # `show` action is inherited from Businesses::CopilotInsightsBaseController
  # and uses the below hooks to customize behavior for this page.

  sig { returns(T.nilable(String)) }
  def self.react_bundle_name
    "copilot-insights-code-generation"
  end

  private

  sig { override.returns(MetricsKey) }
  def copilot_metrics_key = MetricsKey::CodeGenerationMetrics

  sig { override.returns(String) }
  def copilot_page_title = "IDE code generation"

  sig { override.returns(String) }
  def copilot_analytics_category = "copilot_metrics_code_generation_enterprise_dashboard"

  sig { override.returns(Symbol) }
  def sidebar_link = :copilot_insights_code_generation

  sig { override.returns(T::Boolean) }
  def copilot_insights_feature_available? = permissions_object.copilot_insights_code_generation_feature_available?
end
