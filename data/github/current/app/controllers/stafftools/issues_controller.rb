# typed: true
# frozen_string_literal: true

class Stafftools::IssuesController < StafftoolsController

  include Issues::RateLimitsDependency

  before_action :ensure_repo_exists
  before_action :ensure_issue_exists, except: :index
  before_action :redirect_if_pull_request, only: :show
  before_action :ensure_not_pull_request, except: [:index, :show]

  layout "layouts/stafftools/repository/collaboration"

  depends_on_clusters ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    optional: false, only: [:show]

  depends_on_clusters ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    optional: false, only: [:database]

  depends_on_clusters ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Notify,
    ApplicationRecord::Repositories,
    ApplicationRecord::Spokes,
    optional: false, only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :show],
    optional: true

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

  def index
    @issues = current_repository.issues.order("id DESC").paginate \
      page: params[:page] || 1,
      per_page: 25
    @deleted_issues = DeletedIssues::Public.by_repo_desc(current_repository.id)
    render "stafftools/issues/index"
  end

  def show
    query = "data.issue_id:#{this_issue.id} OR (data.user_content_id:#{this_issue.id} AND data.user_content_type:#{this_issue.class} AND action:user_content_edit.*)"
    if driftwood_ade_query?(current_user)
      query = " webevents | where issue_id == #{this_issue.id} or (action startswith 'user_content_edit' and user_content_id == #{this_issue.id} and user_content_type == '#{this_issue.class}')"
    end
    fetch_audit_log_teaser(query)

    notifications_view = Stafftools::RepositoryViews::NotificationsView.new(
      repository: current_repository,
      params: {
        thread: Newsies::Thread.new("Issue", this_issue.id).key,
      },
    )

    render("stafftools/issues/show", locals: { notifications_view: notifications_view })
  end

  def database # rubocop:todo GitHub/UseRestfulActions
    respond_to do |f|
      f.html do
        render "stafftools/issues/database"
      end
    end
  end

  def destroy
    issue_num = this_issue.number

    this_issue.destroy

    instrument \
      "staff.delete_issue",
      user: current_repository.owner,
      repo: current_repository,
      note: "Deleted issue #{current_repository.nwo}##{issue_num}"

    flash[:notice] = "Issue ##{this_issue.number} deleted"
    redirect_to gh_stafftools_repository_issues_path(current_repository)
  end

  def lock # rubocop:todo GitHub/UseRestfulActions
    reason = params[:reason].present? ? params[:reason] : nil
    this_issue.lock(current_user, reason)

    redirect_to gh_stafftools_repository_issues_path(this_issue)
  end

  def unlock # rubocop:todo GitHub/UseRestfulActions
    this_issue.unlock(current_user)

    redirect_to gh_stafftools_repository_issues_path(this_issue)
  end

  private

  def ensure_not_pull_request
    return render_404 if this_issue.pull_request?
  end

  def redirect_if_pull_request
    if this_issue.pull_request?
      redirect_to gh_stafftools_repository_pull_request_path(this_issue)
    end
  end
end
