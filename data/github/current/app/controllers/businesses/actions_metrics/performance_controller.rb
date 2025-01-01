# typed: true
# frozen_string_literal: true


class Businesses::ActionsMetrics::PerformanceController < Businesses::ActionsMetrics::Controller # rubocop:todo GitHub/ControllersShouldHaveTests
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
  depends_on_clusters ApplicationRecord::Copilot

  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
    "Businesses::ActionsMetrics::PerformanceController#index"
  ]

  def show
    render_react_app(
      title: "Actions Performance Metrics",
      disable_ssr: true, # needs to be disabled because page will break otherwise
      page_data: { selected_link: :business_actions_performance_metrics, sidebar: :insights },
      payload: {
        enabled_features: get_feature_flags,
        paths: get_paths,
        scope: :SCOPE_TYPE_ENTERPRISE,
      },
      layout: "layouts/react_business",
    )
  end

  def summary # rubocop:todo GitHub/UseRestfulActions
    render json: get_performance_summary(params, this_business, nil, nil, current_user), content_type: "application/json"
  end
end
