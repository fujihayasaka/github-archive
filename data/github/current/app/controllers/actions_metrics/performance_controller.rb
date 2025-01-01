# typed: true
# frozen_string_literal: true


class ActionsMetrics::PerformanceController < ActionsMetrics::Controller # rubocop:todo GitHub/ControllersShouldHaveTests
  depends_on_clusters ApplicationRecord::Mysql1
  depends_on_clusters ApplicationRecord::Mysql2
  depends_on_clusters ApplicationRecord::Mysql5
  depends_on_clusters ApplicationRecord::Repositories
  depends_on_clusters ApplicationRecord::IamAbilities
  depends_on_clusters ApplicationRecord::Collab
  depends_on_clusters ApplicationRecord::Configurations
  depends_on_clusters ApplicationRecord::NotificationsEntries
  depends_on_clusters ApplicationRecord::Billing
  depends_on_clusters ApplicationRecord::Memex
  depends_on_clusters ApplicationRecord::IssuesPullRequests
  depends_on_clusters ApplicationRecord::Iam

  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
    "ActionsMetrics::PerformanceController#index"
  ]

  def show
    render_react_app(
      title: "Actions Performance Metrics",
      disable_ssr: true, # needs to be disabled because page will break otherwise
      page_data: { selected_link: :repo_graphs },
      payload: {
        enabled_features: get_feature_flags,
        paths: get_paths,
        scope: :SCOPE_TYPE_REPO,
      },
      layout: "layouts/repository/react_insights",
    )
  end

  def summary # rubocop:todo GitHub/UseRestfulActions
    render json: get_performance_summary(params, nil, nil, current_repository, current_user), content_type: "application/json"
  end

  private

  def enforce_metrics_allowed
    render_404 unless current_user&.feature_enabled?(:actions_usage_metrics) && actions_enabled_for_repo?
  end
end
