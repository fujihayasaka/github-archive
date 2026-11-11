# typed: true
# frozen_string_literal: true

class Orgs::CopilotInsights::ImpactController < Orgs::CopilotInsights::Controller
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
    ApplicationRecord::Authnd,
    only: [:show]

  # `show` action is inherited from Orgs::CopilotInsights::Controller
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
  def copilot_analytics_category = "copilot_metrics_impact_org_dashboard"

  sig { override.returns(String) }
  def sidenav_selected_key = "copilot_impact"

  # Impact is gated behind an additional feature flag on top of the base
  # Copilot Insights org dashboard access check.
  sig { void }
  def enforce_copilot_insights_allowed
    render_404 unless permissions_object.copilot_insights_impact_dashboard_accessible?
  end
end
