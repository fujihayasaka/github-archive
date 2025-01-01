# typed: true
# frozen_string_literal: true


class ActionsMetrics::UsageController < ActionsMetrics::Controller # rubocop:todo GitHub/ControllersShouldHaveTests
  include ActionsUsageMetrics::Api::V1

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
    "ActionsMetrics::UsageController#index"
  ]

  def show
    render_react_app(
      title: "Actions Usage Metrics",
      ssr: false, # needs to be disabled because page will break otherwise
      page_data: { selected_link: :repo_graphs }, #TODO UPDATE THIS HERE AND IN OTHER CONTROLLER
      payload: {
        enabled_features: get_feature_flags,
        paths: get_paths,
        scope: :SCOPE_TYPE_REPO,
      },
      layout: "layouts/repository/react_insights",
    )
  end

  def summary # rubocop:todo GitHub/UseRestfulActions
    render json: get_usage_summary(params, nil, current_repository, current_user), content_type: "application/json"
  end

  private

  def enforce_metrics_allowed
    # 404 unless usage feature enabled for current user and repo level enabled for current user
    render_404 unless current_user&.feature_enabled?(:actions_usage_metrics) && current_user&.feature_enabled?(:actions_usage_metrics_repo) && actions_enabled_for_repo?
  end
end
