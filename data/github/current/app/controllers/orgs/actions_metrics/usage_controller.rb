# typed: true
# frozen_string_literal: true


class Orgs::ActionsMetrics::UsageController < Orgs::ActionsMetrics::Controller # rubocop:todo GitHub/ControllersShouldHaveTests
  depends_on_clusters ApplicationRecord::Mysql1
  depends_on_clusters ApplicationRecord::Mysql2
  depends_on_clusters ApplicationRecord::Mysql5
  depends_on_clusters ApplicationRecord::Repositories
  depends_on_clusters ApplicationRecord::IamAbilities
  depends_on_clusters ApplicationRecord::Collab
  depends_on_clusters ApplicationRecord::Copilot
  depends_on_clusters ApplicationRecord::Configurations
  depends_on_clusters ApplicationRecord::NotificationsEntries
  depends_on_clusters ApplicationRecord::Billing

  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
    "Orgs::ActionsMetrics::UsageController#index"
  ]

  def show
    render_react_app(
      title: "Actions Usage Metrics",
      disable_ssr: true, # needs to be disabled because page will break otherwise
      page_data: { selected_link: :insights },
      payload: {
        enabled_features: get_feature_flags,
        paths: get_paths,
        org: this_organization.name,
        scope: :SCOPE_TYPE_ORG,
      },
    )
  end

  def summary # rubocop:todo GitHub/UseRestfulActions
    render json: get_usage_summary(params, nil, this_organization, nil, current_user), content_type: "application/json"
  end

  private

  def enforce_metrics_allowed
    render_404 unless this_organization.actions_usage_metrics_enabled?(current_user)
  end
end
