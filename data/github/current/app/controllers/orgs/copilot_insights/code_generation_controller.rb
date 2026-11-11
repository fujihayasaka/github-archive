# typed: true
# frozen_string_literal: true

class Orgs::CopilotInsights::CodeGenerationController < Orgs::CopilotInsights::Controller
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Copilot,
    ApplicationRecord::Billing,
    only: [:show]

  # `show` action is inherited from Orgs::CopilotInsights::Controller
  # and uses the below hooks to customize behavior for this page.

  sig { returns(T.nilable(String)) }
  def self.react_bundle_name
    "copilot-insights-code-generation"
  end

  private

  sig { override.returns(MetricsKey) }
  def copilot_metrics_key = MetricsKey::CodeGenerationMetrics

  sig { override.returns(String) }
  def copilot_page_title = "Copilot code generation metrics"

  sig { override.returns(String) }
  def copilot_analytics_category = "copilot_metrics_code_generation_org_dashboard"

  sig { override.returns(String) }
  def sidenav_selected_key = "copilot_code_generation"
end
