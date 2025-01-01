# typed: strict
# frozen_string_literal: true

class Orgs::CopilotMetricsInsightsController < Orgs::Controller
  before_action :login_required
  before_action :copilot_metrics_insights_enabled_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Copilot,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries

  sig { returns(String) }
  def self.react_bundle_name
    "copilot-metrics-insights"
  end

  sig { void }
  def index
    respond_to do |format|
      format.html do
        render_react_app(
          payload: {
            copilotAdoptionMetrics: Copilot::Metrics::Adoption.new(owner: this_organization).historical_payload,
            csvDownloadUrl: copilot_metrics_insights_org_insights_url(this_organization, format: :csv),
            inviteMembersLink: settings_org_copilot_seat_management_path(this_organization),
            sidenav:,
          },
          title: "Copilot Metrics Insights"
        )
      end

      format.csv do
        response.headers["Content-Type"] = "text/csv"
        send_data(Copilot::Metrics::Adoption.new(owner: this_organization).historical_csv, type: "text/csv")
      end
    end
  end

  private

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def sidenav
    {
      selectedKey: "copilot-metrics-insights",
      showDependencies: this_organization&.dependency_insights_visible?(current_user),
      showActionsUsageMetrics: this_organization&.actions_usage_metrics_enabled?(current_user),
      showCopilotMetrics: this_organization&.copilot_metrics_enabled?(current_user),
      showApi: true,
      urls: {
        dependency_insights: packages_dashboard_org_insights_path(this_organization),
        actions_usage_metrics: actions_usage_metrics_path(this_organization),
        actions_performance_metrics: actions_performance_metrics_path(this_organization),
        api: api_org_insights_path(this_organization),
        copilot_metrics_insights: copilot_metrics_insights_org_insights_path(this_organization),
      }
    }
  end

  sig { void }
  def copilot_metrics_insights_enabled_required
    render_404 unless this_organization&.copilot_metrics_enabled?(current_user)
  end
end
