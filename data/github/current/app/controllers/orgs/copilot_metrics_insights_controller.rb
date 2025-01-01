# typed: strict
# frozen_string_literal: true

class Orgs::CopilotMetricsInsightsController < Orgs::Controller
  before_action :login_required
  before_action :dotcom_required
  before_action :copilot_metrics_insights_viewer_enabled_required
  before_action :copilot_metrics_insights_catalog_enabled_required, only: [
    :index,
    :copilot_metrics_insights_code_completions_acceptance_rate,
    :copilot_metrics_insights_generated_code_acceptance_rate,
    :copilot_metrics_insights_average_pull_requests_merged_per_developer,
    :copilot_metrics_insights_average_commits_per_developer,
    :copilot_metrics_insights_pull_request_lead_time
  ]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Copilot,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries

  METRICS_DATA_TYPE = T.let({
    adoption: "adoption",
    code_acceptance: "code_acceptance",
    average_contribution: "average_contribution",
    average_pull_request_lead_time: "average_pull_request_lead_time",
  }.freeze, T::Hash[Symbol, String])

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
            sidenav:,
          }.merge(
            Copilot::Metrics::Dashboards::Catalog.new(owner: this_organization).payload
          ),
          page_data: { selected_link: :copilot_metrics_insights },
          title: "Copilot Metrics Insights Catalog"
        )
      end
    end
  end

  sig { void }
  def copilot_metrics_insights_user_onboarding # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.html do
        render_react_app(
          payload: {
            copilotSeatManagementLink: settings_org_copilot_seat_management_path(this_organization),
            csvDownloadUrl: copilot_user_onboarding_org_insights_url(this_organization, format: :csv),
            csvFilename: "copilot-user-onboarding-report_#{this_organization.id}",
            dialogInfo: {
              text: "This breakdown helps highlight engagement patterns, drop-off points, and how different user groups move through onboarding.",
              helpLinks: [
                {
                  text: "What are some examples of other quality signals to consider?",
                  url: "https://resources.github.com/engineering-system-success-playbook/"
                },
                {
                  text: "How are Copilot user engagement levels categorized?",
                  url: "https://gh.io/dashboard-onboard"
                }
              ]
            },
            historicalMetrics: Copilot::Metrics::Dashboards::UserOnboarding.new(owner: this_organization).payload,
            inviteMembersLink: settings_org_copilot_seat_management_path(this_organization),
            metricsDataType: METRICS_DATA_TYPE[:adoption],
            metricsInsightsUrl: copilot_metrics_insights_path,
            metricsTitle: "Copilot user onboarding",
            showCopilotMetricsCatalog: show_metrics_catalog?,
            sidenav:,
          },
          page_data: { selected_link: :copilot_metrics_insights },
          title: "Copilot user onboarding"
        )
      end

      format.csv do
        response.headers["Content-Type"] = "text/csv"
        send_data(Copilot::Metrics::Dashboards::UserOnboarding.new(owner: this_organization).csv, type: "text/csv")
      end
    end
  end

  sig { void }
  def copilot_metrics_insights_code_completions_acceptance_rate # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.html do
        render_react_app(
          payload: {
            csvDownloadUrl: copilot_code_completions_acceptance_rate_org_insights_url(this_organization, format: :csv),
            csvFilename: "copilot-code-completions-acceptance-rate-report_#{this_organization.id}",
            dialogInfo: {
              text: "This breakdown tracks the acceptance rate of Copilot code completion events. This metric should be considered alongside quality signals.",
              helpLinks: [
                {
                  text: "What are some examples of other quality signals to consider?",
                  url: "https://resources.github.com/engineering-system-success-playbook/"
                },
                {
                  text: "How are Copilot user engagement levels categorized?",
                  url: "https://gh.io/dashboard-code-complete"
                }
              ]
            },
            historicalMetrics: Copilot::Metrics::Dashboards::CompletionsAcceptanceRate.new(owner: this_organization).payload,
            inviteMembersLink: settings_org_copilot_seat_management_path(this_organization),
            metricsDataType: METRICS_DATA_TYPE[:code_acceptance],
            metricsInsightsUrl: copilot_metrics_insights_path,
            metricsTitle: "Copilot code completions acceptance rate",
            showCopilotMetricsCatalog: show_metrics_catalog?,
            sidenav:,
          },
          page_data: { selected_link: :copilot_metrics_insights },
          title: "Copilot Metrics Insights"
        )
      end

      format.csv do
        response.headers["Content-Type"] = "text/csv"
        send_data(Copilot::Metrics::Dashboards::CompletionsAcceptanceRate.new(owner: this_organization).csv, type: "text/csv")
      end
    end
  end

  sig { void }
  def copilot_metrics_insights_generated_code_acceptance_rate # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.html do
        render_react_app(
          payload: {
            csvDownloadUrl: copilot_generated_code_acceptance_rate_org_insights_url(this_organization, format: :csv),
            csvFilename: "copilot-generated-code-acceptance-rate-report_#{this_organization.id}",
            dialogInfo: {
              text: "This breakdown tracks the acceptance rate of lines of code written by Copilot. This metric should be considered alongside quality signals.",
              helpLinks: [
                {
                  text: "What are some examples of other quality signals to consider?",
                  url: "https://resources.github.com/engineering-system-success-playbook/"
                },
                {
                  text: "How are Copilot user engagement levels categorized?",
                  url: "https://gh.io/dashboard-code-complete"
                }
              ]
            },
            historicalMetrics: Copilot::Metrics::Dashboards::GeneratedCodeAcceptanceRate.new(owner: this_organization).payload,
            inviteMembersLink: settings_org_copilot_seat_management_path(this_organization),
            metricsDataType: METRICS_DATA_TYPE[:code_acceptance],
            metricsInsightsUrl: copilot_metrics_insights_path,
            metricsTitle: "Copilot generated code acceptance rate",
            showCopilotMetricsCatalog: show_metrics_catalog?,
            sidenav:,
          },
          page_data: { selected_link: :copilot_metrics_insights },
          title: "Copilot Metrics Insights"
        )
      end

      format.csv do
        response.headers["Content-Type"] = "text/csv"
        send_data(Copilot::Metrics::Dashboards::GeneratedCodeAcceptanceRate.new(owner: this_organization).csv, type: "text/csv")
      end
    end
  end

  sig { void }
  def copilot_metrics_insights_average_pull_requests_merged_per_developer # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.html do
        render_react_app(
          payload: {
            csvDownloadUrl: average_pull_requests_merged_per_developer_org_insights_url(this_organization, format: :csv),
            csvFilename: "average-pull-requests-merged-per-developer-report_#{this_organization.id}",
            dialogInfo: {
              text: "This metric should be considered alongside quality signals. Pull request sizes can also vary over time.",
              helpLinks: [
                {
                  text: "What are some examples of other quality signals to consider?",
                  url: "https://resources.github.com/engineering-system-success-playbook/"
                },
                {
                  text: "How are Copilot user engagement levels categorized?",
                  url: "https://gh.io/dashboard-prs"
                }
              ]
            },
            historicalMetrics: Copilot::Metrics::Dashboards::AveragePullRequestsMerged.new(owner: this_organization).payload,
            inviteMembersLink: settings_org_copilot_seat_management_path(this_organization),
            metricsDataType: METRICS_DATA_TYPE[:average_contribution],
            metricsInsightsUrl: copilot_metrics_insights_path,
            metricsTitle: "Average pull requests merged per contributor",
            showCopilotMetricsCatalog: show_metrics_catalog?,
            sidenav:,
          },
          page_data: { selected_link: :copilot_metrics_insights },
          title: "Copilot Metrics Insights"
        )
      end

      format.csv do
        response.headers["Content-Type"] = "text/csv"
        send_data(Copilot::Metrics::Dashboards::AveragePullRequestsMerged.new(owner: this_organization).csv, type: "text/csv")
      end
    end
  end

  sig { void }
  def copilot_metrics_insights_average_commits_per_developer # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.html do
        render_react_app(
          payload: {
            csvDownloadUrl: average_commits_per_developer_org_insights_url(this_organization, format: :csv),
            csvFilename: "average-commits-per-developer-report_#{this_organization.id}",
            dialogInfo: {
              text: "This metric should be considered alongside quality signals. Commit sizes can also vary over time.",
              helpLinks: [
                {
                  text: "What are some examples of other quality signals to consider?",
                  url: "https://resources.github.com/engineering-system-success-playbook/"
                },
                {
                  text: "How are Copilot user engagement levels categorized?",
                  url: "https://gh.io/dashboard-prs"
                }
              ]
            },
            historicalMetrics: Copilot::Metrics::Dashboards::AverageCommits.new(owner: this_organization).payload,
            inviteMembersLink: settings_org_copilot_seat_management_path(this_organization),
            metricsDataType: METRICS_DATA_TYPE[:average_contribution],
            metricsInsightsUrl: copilot_metrics_insights_path,
            metricsTitle: "Average commits per contributor",
            showCopilotMetricsCatalog: show_metrics_catalog?,
            sidenav:,
          },
          page_data: { selected_link: :copilot_metrics_insights },
          title: "Copilot Metrics Insights"
        )
      end

      format.csv do
        response.headers["Content-Type"] = "text/csv"
        send_data(Copilot::Metrics::Dashboards::AverageCommits.new(owner: this_organization).csv, type: "text/csv")
      end
    end
  end

  sig { void }
  def copilot_metrics_insights_pull_request_lead_time # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.html do
        render_react_app(
          payload: {
            csvDownloadUrl: pull_request_lead_time_org_insights_url(this_organization, format: :csv),
            csvFilename: "pull-request-lead-time-report_#{this_organization.id}",
            dialogInfo: {
              text: "This metric excludes pull requests open for over 90 days and helps highlight potential bottlenecks. Consider alongside quality signals.",
              helpLinks: [
                {
                  text: "What are some examples of other quality signals to consider?",
                  url: "https://resources.github.com/engineering-system-success-playbook/"
                },
                {
                  text: "How are Copilot user engagement levels categorized?",
                  url: "https://gh.io/dashboard-prs"
                }
              ]
            },
            historicalMetrics: Copilot::Metrics::Dashboards::PullRequestLeadTime.new(owner: this_organization).payload,
            inviteMembersLink: settings_org_copilot_seat_management_path(this_organization),
            metricsDataType: METRICS_DATA_TYPE[:average_pull_request_lead_time],
            metricsInsightsUrl: copilot_metrics_insights_path,
            metricsTitle: "Average pull request lead time",
            showCopilotMetricsCatalog: show_metrics_catalog?,
            sidenav:,
          },
          page_data: { selected_link: :copilot_metrics_insights },
          title: "Copilot Metrics Insights"
        )
      end

      format.csv do
        response.headers["Content-Type"] = "text/csv"
        send_data(Copilot::Metrics::Dashboards::PullRequestLeadTime.new(owner: this_organization).csv, type: "text/csv")
      end
    end
  end

  private

  sig { returns(T::Boolean) }
  memoize def show_metrics_catalog?
    this_organization&.copilot_metrics_catalog_enabled?(current_user)
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def sidenav
    {
      selectedKey: "copilot_metrics_insights",
      showDependencies: this_organization&.dependency_insights_visible?(current_user),
      showActionsUsageMetrics: this_organization&.actions_usage_metrics_enabled?(current_user),
      showCopilotMetricsViewer: this_organization&.copilot_metrics_viewer_enabled?(current_user),
      showCopilotMetricsCatalog: show_metrics_catalog?,
      showApi: true,
      urls: {
        dependency_insights: packages_dashboard_org_insights_path(this_organization),
        actions_usage_metrics: actions_usage_metrics_path(this_organization),
        actions_performance_metrics: actions_performance_metrics_path(this_organization),
        api: api_org_insights_path(this_organization),
        copilot_metrics_insights: copilot_metrics_insights_path,
      }
    }
  end

  sig { returns(String) }
  def copilot_metrics_insights_path
    if feature_enabled_globally_or_for_current_user?(:copilot_metrics_insights_navigator) ||
        this_organization&.feature_enabled?(:copilot_metrics_insights_navigator) ||
        this_organization&.business&.feature_enabled?(:copilot_metrics_insights_navigator)
      copilot_metrics_insights_catalog_org_insights_path(this_organization)
    else
      copilot_user_onboarding_org_insights_path(this_organization)
    end
  end

  sig { void }
  def copilot_metrics_insights_viewer_enabled_required
    render_404 unless this_organization&.copilot_metrics_viewer_enabled?(current_user)
  end

  sig { void }
  def copilot_metrics_insights_catalog_enabled_required
    render_404 unless show_metrics_catalog?
  end
end
