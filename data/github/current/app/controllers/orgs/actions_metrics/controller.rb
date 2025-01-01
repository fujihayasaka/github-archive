# typed: true
# frozen_string_literal: true

class Orgs::ActionsMetrics::Controller < Orgs::Controller # rubocop:todo GitHub/ControllersShouldHaveTests
  # This controller shouldn't be called directly, and performance or usage should be used instead

  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::JsonDependency
  include ActionsMetrics::ApiUtils

  # Allow pagination above the cap of 100 for customers with over 100 pages of metrics
  skip_before_action :cap_pagination

  before_action :login_required
  before_action :organization_read_required
  before_action :enforce_metrics_allowed
  before_action :try_parse_json_params, only: [:index, :export, :export_status, :summary]
  around_action :set_log_context

  depends_on_clusters ApplicationRecord::Mysql1
  depends_on_clusters ApplicationRecord::Mysql2
  depends_on_clusters ApplicationRecord::Mysql5
  depends_on_clusters ApplicationRecord::Repositories
  depends_on_clusters ApplicationRecord::IamAbilities
  depends_on_clusters ApplicationRecord::Collab
  depends_on_clusters ApplicationRecord::Configurations
  depends_on_clusters ApplicationRecord::NotificationsEntries
  depends_on_clusters ApplicationRecord::Billing

  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
    "Orgs::ActionsMetrics::Controller#index"
  ]

  # Method must be added here if it is a post handler
  allow_verified_fetch only: [:index, :export, :export_status, :summary]

  def self.react_bundle_name
    "actions-metrics"
  end

  def index
    render json: get_metrics_data(params, nil, this_organization, nil, current_user), content_type: "application/json"
  end

  def repositories # rubocop:todo GitHub/UseRestfulActions
    render json: get_repositories(params, this_organization, current_user, user_session), content_type: "application/json"
  end

  def workflows # rubocop:todo GitHub/UseRestfulActions
    render json: get_workflows(params, nil, this_organization, nil, current_user), content_type: "application/json"
  end

  def jobs # rubocop:todo GitHub/UseRestfulActions
    render json: get_jobs(params, nil, this_organization, nil, current_user), content_type: "application/json"
  end

  def runner_labels # rubocop:todo GitHub/UseRestfulActions
    render json: get_runner_labels(params, nil, this_organization, nil, current_user), content_type: "application/json"
  end

  def export_status # rubocop:todo GitHub/UseRestfulActions
    render json: get_export_status(params, nil, this_organization, nil, current_user), content_type: "application/json"
  end

  def export # rubocop:todo GitHub/UseRestfulActions
    render json: start_export(params, nil, this_organization, nil, current_user), content_type: "application/json"
  end

  private

  def enforce_metrics_allowed
    raise NotImplementedError, "Authorization checks must be implemented"
  end

  def get_feature_flags
    {
      dependency_insights_enabled: this_organization.dependency_insights_visible?(current_user),
      api_insights_enabled: this_organization.api_insights_enabled?(current_user),
      actions_usage_metrics: this_organization.actions_usage_metrics_enabled?(current_user),
      copilot_metrics_onboarding_timeline_page: this_organization.copilot_metrics_viewer_enabled?(current_user),
      copilot_metrics_insights_navigator: this_organization.copilot_metrics_catalog_enabled?(current_user),
    }
  end

  def get_paths
    {
      actions_performance_metrics: actions_performance_metrics_path(this_organization),
      actions_usage_metrics: actions_usage_metrics_path(this_organization),
      dependency_insights: packages_dashboard_org_insights_path(this_organization),
      api: api_org_insights_path(this_organization),
      copilot_metrics_insights: copilot_metrics_insights_path,
    }
  end

  sig { returns(String) }
  def copilot_metrics_insights_path
    if this_organization&.feature_enabled?(:copilot_metrics_insights_navigator) || this_organization&.business&.feature_enabled?(:copilot_metrics_insights_navigator)
      copilot_metrics_insights_catalog_org_insights_path(this_organization)
    else
      copilot_user_onboarding_org_insights_path(this_organization)
    end
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  memoize def logging_context
    {
      "enduser.id": current_user&.display_login,
      "gh.enduser.id": current_user&.id,
      "gh.org.id": current_organization.id,
      "gh.org.login": current_organization.display_login,
    }
  end

  sig { params(block: T.proc.void).void }
  def set_log_context(&block)
    GitHub.logger.with_named_tags(logging_context) { yield }
  end
end
