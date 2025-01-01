# typed: true
# frozen_string_literal: true

class Stafftools::PullRequestsController < StafftoolsController
  before_action :ensure_repo_exists
  before_action :ensure_pull_request_exists, except: [:purge, :reindex, :stop]

  layout "layouts/stafftools/repository/collaboration"

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Ballast,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Collab,
    ApplicationRecord::Spokes,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    only: [:show]

  depends_on_clusters ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Ballast,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    only: [:database]

  depends_on_clusters ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    optional: true, only: [:database]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show], optional: true

  def show
    load_diff_summary
    @deployment_events_count = IssueEvent.deployments.where(issue: this_pull.issue).count
    @visible_events_count = IssueEvent.visible.where(issue: this_pull.issue).count
    query = "data.pull_request_id:#{this_pull.id} OR (data.user_content_id:#{this_pull.issue.id} AND data.user_content_type:Issue AND action:user_content_edit.*)"
    if GitHub.driftwood_ade_queries_enabled?
      query = <<~KQL
        webevents
        | where repo_id == #{this_pull.repository.id} and data.pull_request_id == "#{this_pull.id}"
        or (user_content_id == #{this_pull.issue.id} and user_content_type == "Issue" and action startswith "user_content_edit")
      KQL
    end
    fetch_audit_log_teaser(query)

    notifications_view = Stafftools::RepositoryViews::NotificationsView.new(
      repository: current_repository,
      params: {
        thread: Newsies::Thread.new("Issue", this_pull.issue.id).key,
      },
    )

    render("stafftools/pull_requests/show", locals: { notifications_view: notifications_view })
  end

  def database # rubocop:todo GitHub/UseRestfulActions
    render "stafftools/pull_requests/database"
  end

  # Updates the head and base SHA for a pull request to be current with the
  # underlying git repository. Sometimes useful when a pull request fails to
  # update due to post-receive failure.
  def sync # rubocop:todo GitHub/UseRestfulActions
    this_pull.repository.network.increment_cache_version!

    if this_pull.catch_up
      flash[:notice] = "Pull Request synchronized"
    else
      flash[:error] = "No changes detected"
    end
    redirect_to :back
  end

  def destroy
    issue = this_pull.issue
    pull_num = this_pull.number

    this_pull.destroy_tracking_refs
    this_pull.destroy
    issue.reload # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    issue.destroy # domain-isolation-query-violation:ignore:packages/issues (DELETE, SELECT)

    instrument \
      "staff.delete_pull_request",
      user: current_repository.owner,
      repo: current_repository,
      note: "Deleted pull request #{current_repository.nwo}##{pull_num}"

    flash[:notice] = "Pull request ##{pull_num} deleted"
    redirect_to gh_stafftools_repository_issues_path(current_repository)
  end

  # Stop the currently running reindex job
  def stop # rubocop:todo GitHub/UseRestfulActions
    repair_job = RepairPullRequestsIndexJob.new("pull-requests", repo_id: current_repository.id)
    if repair_job.exists? && repair_job.enabled?
      repair_job.disable
      flash[:notice] = "Pull request reindexing stopped"
    end
    redirect_to :back
  end

  # Reindex the repo's pull requests for search
  def reindex # rubocop:todo GitHub/UseRestfulActions
    purge = params[:purge] == "true" ? true : false
    if current_user.feature_flag_enabled?(:elastomer_use_repair_job_for_repo_reindex, default: false)
      repair_job = RepairPullRequestsIndexJob.new("pull-requests", repo_id: current_repository.id)
      repair_job.reset!
      repair_job.enable
      repair_job.start(10)
    else
      current_repository.reindex_pull_requests(purge)
    end
    flash[:notice] = "Reindexing #{current_repository.pull_requests.count} pull requests ..."
    redirect_to :back
  end

  # Synchronize the search index for a single PR.
  def sync_search_index # rubocop:todo GitHub/UseRestfulActions
    this_pull.synchronize_search_index
    flash[:notice] = "Reindexing pull request ##{this_pull.number}"

    redirect_to :back
  end

  # Synchronize the status attribute for a single PR.
  def sync_status # rubocop:todo GitHub/UseRestfulActions
    this_pull.sync_status_with_issue
    flash[:notice] = "Synchronizing status for pull request ##{this_pull.number}"

    redirect_to :back
  end

  def maintain_tracking_ref # rubocop:todo GitHub/UseRestfulActions
    begin
      this_pull.maintain_tracking_ref_with_retries(current_user)
      flash[:notice] = "Maintenance complete"
    rescue Git::Ref::ComparisonMismatch
      flash[:error] = "Something went wrong - unable to maintain tracking ref"
    end

    redirect_to :back
  end

  def purge # rubocop:todo GitHub/UseRestfulActions
    current_repository.purge_pull_requests
    flash[:notice] = "Purging pull requests from the search index ..."
    redirect_to :back
  end

  private

  memoize def this_pull
    PullRequest.with_number_and_repo \
      params[:id].to_i,
      current_repository,
      include: [{ issue: { comments: :user } }]
  end
  helper_method :this_pull

  def pull_request
    this_pull
  end
  helper_method :pull_request

  def ensure_pull_request_exists
    render_404 if this_pull.nil?
  end

  def request_reflog_data(via)
    {
      real_ip: request.remote_ip,
      repo_name: current_repository.name_with_owner,
      repo_public: current_repository.public?,
      user_login: current_user.login,
      user_agent: request.user_agent,
      from: GitHub.context[:from],
      via: via,
    }
  end

  def counters
    {
      open: current_repository.pull_requests.joins(:issue).where(issues: { state: "open" }).count,
      closed: current_repository.pull_requests.joins(:issue).where(issues: { state: "closed" }).count,
    }
  end

  def load_diff_summary
    comparison = this_pull.historical_comparison
    comparison.set_diff_options(
      use_summary: true,
      timeout: request_time_left / 2
    )

    @diffs = comparison.async_diff.sync
  end
end
