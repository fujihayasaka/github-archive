# typed: true
# frozen_string_literal: true

class Businesses::ActionsMetrics::Controller < Businesses::BusinessController # rubocop:todo GitHub/ControllersShouldHaveTests
  # This controller shouldn't be called directly, and performance or usage should be used instead

  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::JsonDependency
  include ActionsMetrics::ApiUtils

  # Allow pagination above the cap of 100 for customers with over 100 pages of metrics
  skip_before_action :cap_pagination

  before_action :login_required
  before_action :enforce_metrics_allowed
  before_action :business_full_plan_required
  before_action :try_parse_json_params, only: [:index, :export, :export_status, :summary]

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
    "Businesses::ActionsMetrics::Controller#index"
  ]

  # Method must be added here if it is a post handler
  allow_verified_fetch only: [:index, :export, :export_status, :summary]

  def self.react_bundle_name
    "actions-metrics"
  end

  def index
    render json: get_metrics_data(params, this_business, nil, nil, current_user), content_type: "application/json"
  end

  def workflows # rubocop:todo GitHub/UseRestfulActions
    render json: get_workflows(params, this_business, nil, nil, current_user), content_type: "application/json"
  end

  def jobs # rubocop:todo GitHub/UseRestfulActions
    render json: get_jobs(params, this_business, nil, nil, current_user), content_type: "application/json"
  end

  def runner_labels # rubocop:todo GitHub/UseRestfulActions
    render json: get_runner_labels(params, this_business, nil, nil, current_user), content_type: "application/json"
  end

  def export_status # rubocop:todo GitHub/UseRestfulActions
    render json: get_export_status(params, this_business, nil, nil, current_user), content_type: "application/json"
  end

  def export # rubocop:todo GitHub/UseRestfulActions
    render json: start_export(params, this_business, nil, nil, current_user), content_type: "application/json"
  end

  def orgs # rubocop:todo GitHub/UseRestfulActions
    render json: orgs_matching_query, content_type: "application/json"
  end

  private

  def enforce_metrics_allowed
    render_404 unless this_business.actions_usage_metrics_enabled?(current_user)
  end

  def get_feature_flags
    {
      actions_usage_metrics: current_user&.feature_enabled?(:actions_usage_metrics),
    }
  end

  def get_paths
    {}
  end

  def orgs_matching_query
    # used for autocomplete
    search_term = get_search_query(params)

    if search_term != nil && search_term != ""
      query = this_business.organizations.where("`display_login` like ?", "%#{search_term}%").limit(suggestion_limit)
      query.to_a.pluck(:display_login)
    else
      results = this_business.organizations.limit(suggestion_limit)
      results.to_a.pluck(:display_login)
    end
  end

end
