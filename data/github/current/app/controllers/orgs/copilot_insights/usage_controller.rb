# typed: true
# frozen_string_literal: true

class Orgs::CopilotInsights::UsageController < Orgs::CopilotInsights::Controller
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

  private

  sig { override.returns(MetricsKey) }
  def copilot_metrics_key = MetricsKey::UsageMetrics

  sig { override.returns(String) }
  def copilot_page_title = "Copilot usage metrics"

  sig { override.returns(String) }
  def copilot_analytics_category = "copilot_metrics_usage_org_dashboard"

  sig { override.returns(String) }
  def sidenav_selected_key = "copilot_usage"
end
