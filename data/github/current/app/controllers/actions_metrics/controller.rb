# typed: true
# frozen_string_literal: true

class ActionsMetrics::Controller < AbstractRepositoryController # rubocop:todo GitHub/ControllersShouldHaveTests
  # This controller shouldn't be called directly, and performance or usage should be used instead

  extend T::Sig

  include ReactHelper
  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::JsonDependency
  include ActionsMetrics::ApiUtils

  # Allow pagination above the cap of 100 for customers with over 100 pages of metrics
  skip_before_action :cap_pagination

  before_action :login_required
  before_action :enforce_metrics_allowed
  before_action :try_parse_json_params, only: [:index, :export, :export_status]

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
    "Orgs::ActionsMetrics::Controller#index"
  ]

  # Method must be added here if it is a post handler
  allow_verified_fetch only: [:index, :export, :export_status]

  def self.react_bundle_name
    "actions-metrics"
  end

  def index
    render json: get_metrics_data(params, nil, current_repository, current_user), content_type: "application/json"
  end

  def workflows # rubocop:todo GitHub/UseRestfulActions
    render json: get_workflows(params, nil, current_repository, current_user), content_type: "application/json"
  end

  def jobs # rubocop:todo GitHub/UseRestfulActions
    render json: get_jobs(params, nil, current_repository, current_user), content_type: "application/json"
  end

  def export_status # rubocop:todo GitHub/UseRestfulActions
    render json: get_export_status(params, nil, current_repository), content_type: "application/json"
  end

  def export # rubocop:todo GitHub/UseRestfulActions
    render json: start_export(params, nil, current_repository, current_user), content_type: "application/json"
  end

  private

  def enforce_metrics_allowed
    raise NotImplementedError, "Authorization checks must be implemented"
  end

  def actions_enabled_for_repo?
    return false unless !current_repository.nil? && ((GitHub.actions_enabled? && !current_repository.actions_disabled?) || show_only_required_workflows?)
    true
  end

  def show_only_required_workflows?
    current_repository.actions_disabled? && !current_repository.actions_disabled_by_owner? && current_repository.workflows.required.not_deleted.any?
  end

  def get_paths
    {}
  end

  def get_feature_flags
    {}
  end
end
