# typed: true
# frozen_string_literal: true

class MilestonesController < AbstractRepositoryController

  include Issues::RateLimitsDependency
  include IssuesReactHelper

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
    optional: false, only: [:index, :show]

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
    ApplicationRecord::Repositories,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Spokes,
    optional: false, only: [:edit, :new]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :edit, :new, :show], optional: true

  CLOSED_PER_PAGE = 25
  OPEN_PER_PAGE = 100
  MAX_PER_PAGE = GitHub::Prioritizable::MAXIMUM_PRIORITIZABLE_ITEM_COUNT

  MILESTONES_PER_PAGE = 50
  MAX_PAGINATION = 500

  before_action :writable_repository_required, except: [:index, :show]
  before_action :milestone_must_exist, except: %w(index new)
  before_action :modifiers_only, except: [:index, :show]

  layout "repository"

  javascript_bundle :"issues-react", only: [:show, :index, :edit, :new]

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
    issue_react_milestone_index_handler
  end

  def new
    issue_react_milestone_new_handler
  end

  def show
    issue_react_milestone_show_handler
  end

  def edit
    issue_react_milestone_edit_handler
  end

  protected

  memoize def current_milestone
    if params[:id]
      current_repository.milestones.find_by_number(params[:id])
    elsif params[:number]
      current_repository.milestones.find_by_number(params[:number])
    elsif params[:slug]
      current_repository.milestones.find_by_slug(params[:slug])
    end
  end
  helper_method :current_milestone

  def milestone_must_exist
    unless current_milestone
      render_404
    end
  end

  def modifiers_only
    return redirect_to_login unless logged_in?
    return redirect_to "/" unless current_repository
    redirect_to "/" unless current_user_can_push?
  end

  private

  def milestone_params
    params.require(:milestone).permit %i[title description due_on state body]
  end

  def max_pagination_page
    MAX_PAGINATION
  end
end
