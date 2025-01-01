# typed: true
# frozen_string_literal: true

class LabelsController < AbstractRepositoryController
  include LabelEducationHelper
  include Issues::RateLimitsDependency
  include IssuesReactHelper

  before_action :pushers_only, except: [:index, :show]
  before_action :writable_repository_required, except: [:index, :show]
  layout "repository", only: [:index]

  depends_on_clusters ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    optional: false, only: [:show]

  depends_on_clusters ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Notify,
    ApplicationRecord::Repositories,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Spokes,
    optional: false, only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index], optional: true

  javascript_bundle :"issues-react", only: [:index]

  RATE_LIMITS_FEATURES = [
    :issues_service_mutative_actions_rate_limits, # are rate limits for issues-owned controller/actions enabled
    :issues_service_mutative_actions_rate_limits_new_max, # what are the new max rate limits for issues-owned controller/actions
    :issues_rate_limit_circuit_breaker, # whether to enable the circuit breaker for spammy users creating issues via issues#create
  ]

  preload_features RATE_LIMITS_FEATURES

  rate_limit_requests \
    max: :issues_service_rate_limits_max,
    ttl: 1.hour,
    key: :default_rate_limit_key,
    at_limit: :issues_service_rate_limits_at_limit,
    if: :issues_service_rate_limits_enabled?

  rate_limit_requests \
    only: [:index],
    max: ISSUES_BOT_RATE_LIMIT_MAX,
    ttl: 1.minute,
    key: :issues_bot_rate_limit_key,
    if: :issues_bot_rate_limiting_enabled?,
    at_limit: :issues_bot_rate_limit_at_limit

  def index
    issue_react_label_index_handler
  end

  def show
    if label = current_repository.labels.find_by_name(params[:id])
      redirect_to url_for(controller: :issues, action: :index, labels: label.name)
    else
      render_404
    end
  end
end
