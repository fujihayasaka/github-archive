# typed: true
# frozen_string_literal: true

# rubocop:todo GitHub/RailsControllerRenderLiteral

class PullRequestPartialsController < AbstractRepositoryController
  include ApplicationController::PartialRenderWithLayoutDependency
  include ApplicationController::VerifiedFetchDependency
  include ShowPartial
  include ControllerMethods::Codespaces
  include TimelineHelper
  include ControllerMethods::PullRequests
  include PullRequests::FileTreeHelper
  include PullRequests::ReactDependency
  include GateRequestHelper

  layout false

  before_action :no_cache
  before_action :find_pull_request
  before_action :set_page_responsive

  rescue_from_timeout_without_replay only: [:conversation_content], if: :should_gracefully_degrade_from_timeout? do |boom|
    T.bind(self, PullRequestPartialsController)

    tags = ["with_retry:true", "graceful_timeout_threshold:#{graceful_timeout_threshold}"]
    GitHub.dogstats.increment "pull_request.conversation_content.graceful_timeout", tags: tags

    Failbot.report(boom)
    render partial: "site/pull_request_timeline_timeout"
  end

  allow_verified_fetch only: [:processing_indicator]

  depends_on_clusters(
    # Required for `find_pull_request`
    ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::IssuesPullRequests,

    # Required for `AbstractRepositoryController#ensure_advisory_workspace_allowed`
    ApplicationRecord::Collab,

    # Required for `RepositoryControllerMethods#ask_the_gatekeeper`
    ApplicationRecord::IamAbilities,

    # Required for
    # `ApplicationController::ConditionalAccessDependency#perform_conditional_access_checks`
    ApplicationRecord::Configurations,
  )

  depends_on_clusters(
    ApplicationRecord::Billing,
    ApplicationRecord::Spokes,
    ApplicationRecord::Copilot,
    ApplicationRecord::Iam,
    ApplicationRecord::Ballast,
    ApplicationRecord::Memex,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Notify,
    only: [:body],
  )

  depends_on_clusters(
    ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Iam,
    ApplicationRecord::Memex,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Notify,
    ApplicationRecord::Spokes,
    only: [:deployed_event]
  )

  depends_on_clusters(
    ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Copilot,
    ApplicationRecord::Iam,
    ApplicationRecord::Memex,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Notify,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::RepositoriesPushes,
    ApplicationRecord::Spokes,
    only: [:deployments_box, :timeline] # timeline renders the deployments_box partial so it needs the same dependencies
  )

  depends_on_clusters(
    ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Copilot,
    ApplicationRecord::Iam, # Required for `Repository#async_batch_most_capable_user_role_for_actor`
    ApplicationRecord::Memex,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Notify,
    ApplicationRecord::Permissions,
    ApplicationRecord::RepositoriesPushes,
    ApplicationRecord::Spokes,
    optional: false,
    only: [:merging]
  )
  depends_on_clusters(
    ApplicationRecord::Mysql5,
    ApplicationRecord::RepositoriesActionsChecks,
    optional: true,
    only: [:merging]
  )

  depends_on_clusters(
    ApplicationRecord::Ballast,
    ApplicationRecord::Copilot,
    ApplicationRecord::Memex,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Permissions,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Spokes,
    only: [:review]
  )

  depends_on_clusters(
    ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Memex,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Spokes,
    only: [:state]
  )

  depends_on_clusters(
    ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Copilot,
    ApplicationRecord::Iam,
    ApplicationRecord::Memex,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Notify,
    ApplicationRecord::Permissions,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Spokes,
    only: [:unread_timeline]
  )

  depends_on_clusters(
    ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Copilot,
    ApplicationRecord::Iam,
    ApplicationRecord::Memex,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Notify,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Spokes,
    only: [:commit_status_icon]
  )

  depends_on_clusters(
    ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Iam,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Notify,
    ApplicationRecord::Spokes,
    only: [:form_actions]
  )

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:form_actions], optional: true

  depends_on_clusters(
    ApplicationRecord::Iam,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Spokes,
    only: [:state_button_wrapper]
  )

  depends_on_clusters(
    ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Copilot,
    ApplicationRecord::Iam,
    ApplicationRecord::Memex,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Notify,
    ApplicationRecord::RepositoriesPushes,
    ApplicationRecord::Spokes,
    only: [:title]
  )

  depends_on_clusters(
    ApplicationRecord::Mysql5,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Spokes,
    only: [:changed_commits]
  )

  depends_on_clusters(
    ApplicationRecord::Billing,
    ApplicationRecord::Spokes,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Memex,
    ApplicationRecord::Permissions,
    only: [:sidebar]
  )
  depends_on_clusters(
    ApplicationRecord::Copilot,
    ApplicationRecord::Iam,
    optional: true, only: [:sidebar]
  )

  depends_on_clusters(
    ApplicationRecord::Ballast,
    ApplicationRecord::Copilot,
    ApplicationRecord::Iam,
    ApplicationRecord::Memex,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Notify,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Spokes,
    only: [:tabs]
  )

  depends_on_clusters(
    ApplicationRecord::Ballast,
    ApplicationRecord::Memex,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Spokes,
    only: [:commit_status_checks]
  )

  depends_on_clusters(
    ApplicationRecord::Ballast,
    ApplicationRecord::Memex,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Spokes,
    only: [:file_tree]
  )

  depends_on_clusters(
    ApplicationRecord::Mysql5,
    ApplicationRecord::RepositoriesActionsChecks,
    optional: true, only: [:file_tree]
  )

  depends_on_clusters(
    ApplicationRecord::Spokes,
    ApplicationRecord::RepositoriesPushes,
    only: [:processing_indicator]
  )

  depends_on_clusters(
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql1,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Permissions,
    ApplicationRecord::Repositories,
    ApplicationRecord::RepositoriesPushes,
    ApplicationRecord::Spokes,
    optional: false, only: [:conversation]
  )

  depends_on_clusters(
    ApplicationRecord::Ballast,
    ApplicationRecord::Copilot,
    ApplicationRecord::Memex,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Notify,
    ApplicationRecord::RepositoriesActionsChecks,
    optional: true, only: [:conversation]
  )

  depends_on_clusters(
    ApplicationRecord::Ballast,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Repositories,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Iam,
    ApplicationRecord::Spokes,
    ApplicationRecord::Memex,
    ApplicationRecord::RepositoriesPushes,
    only: [:conversation_content]
  )

  depends_on_clusters(
    ApplicationRecord::Mysql5,
    ApplicationRecord::Copilot,
    optional: true,
    only: [:conversation_content]
  )

  depends_on_clusters(
    ApplicationRecord::Iam,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Permissions,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::RepositoriesPushes,
    optional: false, only: [:checks_partial]
  )

  depends_on_clusters(
    ApplicationRecord::Ballast,
    ApplicationRecord::Memex,
    ApplicationRecord::Copilot,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Notify,
    optional: true, only: [:checks_partial]
  )

  rate_limit_requests \
    only: [:conversation],
    max: GitHub::RateLimitedRequest::DEFAULT_RATE_LIMIT_MAX,
    ttl: GitHub::RateLimitedRequest::DEFAULT_RATE_LIMIT_TTL,
    if: :should_rate_limit_request?,
    key: :default_rate_limit_key

  def conversation # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.json do
        return render_404 unless conversations_react_enabled?

        render_rails_partial_payload(payload: conversation_partial_payload(@pull))
      end
    end
  end

  # Serves conversation content as an HTML fragment for graceful timeout retries.
  # When the Voltron SSR request for conversation_content times out, it renders an
  # <include-fragment> pointing here. This endpoint goes through normal
  # AbstractRepositoryController access control (which returns 404 for unauthorized
  # access) instead of the Voltron fragment controller's HMAC-based auth.
  def conversation_content # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.html do
        timeout_seconds = should_gracefully_degrade_from_timeout? ? graceful_timeout_threshold : nil
        GitHub::Timer.timeout(timeout_seconds) do
          render_conversation_content_html(@pull)
        end
      end
    end
  end

  def timeline_actions # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.json do
        return render_404 unless conversations_react_enabled?

        render_rails_partial_payload(payload: conversation_timeline_actions_payload(@pull))
      end
    end
  end

  def timeline # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.json do
        return render_404 unless conversations_react_enabled?

        render_rails_partial_payload(payload: conversation_timeline_payload(@pull))
      end
    end
  end

  def checks_partial # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.json do
        return render_404 unless checks_react_enabled?

        render_rails_partial_payload(payload: checks_partial_payload(@pull))
      end
    end
  end

  def deployments_box # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.html do
        render partial: "pull_requests/deployments_box", object: @pull, locals: { pull: @pull }, layout: partial_fragment_layout
      end
    end
  end

  def description_branches_dropdown # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.html do
        render partial: "pull_requests/description_branches_dropdown", object: @pull, locals: { pull: @pull }, layout: partial_fragment_layout
      end
    end
  end

  def form_actions # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.html do
        render partial: "pull_requests/form_actions", object: @pull, locals: { pull: @pull }, layout: partial_fragment_layout
      end
    end
  end

  def merging # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.html do
        render partial: "pull_requests/merging", object: @pull, locals: { pull: @pull, merge_type: params[:merge_type] }, layout: partial_fragment_layout
      end
    end
  end

  def sidebar # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.html do
        render partial: "pull_requests/sidebar", object: @pull, locals: { pull: @pull }, layout: partial_fragment_layout
      end

      format.json do
        return render_404 unless conversations_react_enabled?

        render_rails_partial_payload(payload: conversation_sidebar_partial_payload(pull: @pull, voltron: false))
      end
    end
  end

  def state # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.html do
        render partial: "pull_requests/state", object: @pull, locals: { pull: @pull }, layout: partial_fragment_layout
      end
    end
  end

  def state_button_wrapper # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.html do
        render partial: "pull_requests/state_button_wrapper", object: @pull, locals: { pull: @pull }, layout: partial_fragment_layout
      end
    end
  end

  def tabs # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.html do
        render partial: "pull_requests/tabs", object: @pull, locals: { pull: @pull }, layout: partial_fragment_layout
      end
    end
  end

  def title # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.html do
        render partial: "pull_requests/title", object: @pull, locals: { pull: @pull, sticky: params[:sticky] == "true" }, layout: partial_fragment_layout
      end
    end
  end

  def deployed_event # rubocop:todo GitHub/UseRestfulActions
    deployed_event = @pull.issue.events.find_by(id: params[:event_id], event: "deployed")
    return head :ok unless deployed_event

    respond_to do |format|
      format.html do
        render PullRequests::TimelineEvents::DeployedEventComponent.new(pull_request: @pull, issue_event: deployed_event), layout: component_fragment_layout
      end
    end
  end

  def commit_status_checks # rubocop:todo GitHub/UseRestfulActions
    event = @pull.issue.events.find_by(id: params[:event_id])
    return head :not_found unless event

    respond_to do |format|
      format.html do
        render PullRequests::TimelineEvents::CommitStatusChecksComponent.new(pull_request: @pull, issue_event: event), layout: component_fragment_layout
      end
    end
  end

  def links # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.html do
        render partial: "pull_requests/links", locals: { pull: @pull, has_github_issues: ActiveModel::Type::Boolean.new.cast(params[:has_github_issues]) }, layout: false
      end
    end
  end

  def review # rubocop:todo GitHub/UseRestfulActions
    review = @pull.reviews.find_by(id: params[:review_id])
    return head :not_found unless review

    # We need to preload code scanning review comments here even if this pull_request_review is not from
    # code scanning in case some of its comments are replies to a code scanning review comment. In such case,
    # we will need to check if the code scanning review comment correpsonds to a fixed or dismissed alert
    # so we know whether to make the comment collapsed by default.
    CodeScanning::ReviewCommentComponent.preload_review_comments(pull_request: @pull)

    respond_to do |format|
      format.html do
        render PullRequests::ReviewComponent.new(pull_request: @pull, pull_request_review: review), layout: component_fragment_layout
      end
    end
  end

  def unread_timeline # rubocop:todo GitHub/UseRestfulActions
    timeline_owner = PullRequest::ShowLoader.issue_node(
      @pull,
      current_repository,
      current_user,
      cap_filter: cap_filter,
      pagination_params: { per_page: params[:timeline_per_page] || DEFAULT_PAGE_SIZE, before_cursor: params[:before_cursor], after_cursor: params[:after_cursor], timeline_since: params[:since] }
    )

    return head :not_found unless timeline_owner.timeline_loader.timeline_start.async_page_count.sync > 0

    respond_to do |format|
      format.html do
        render partial: "pull_requests/timeline", object: @pull, locals: { pull_node: timeline_owner }, layout: partial_fragment_layout
      end
    end
  end

  def changed_commits # rubocop:todo GitHub/UseRestfulActions
    sha = params[:sha] || @pull.head_sha

    commits = Commit.prefill_combined_statuses(@pull.changed_commits, current_repository)
    selected_commit = commits.find { |commit| commit.oid == sha } || commits.last

    check_run_id = params[:check_run_id]
    selected_check_run = Checks.domain.check_runs.for_id(check_run_id.to_i, repository_id: current_repository.id) if check_run_id

    respond_to do |format|
      format.html do
        render partial: "pull_requests/changed_commits", layout: partial_fragment_layout, locals: {
          pull: @pull,
          commits: commits,
          selected_commit: selected_commit,
          selected_check_run: selected_check_run
        }
      end
    end
  end

  def body # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.html do
        render PullRequests::BodyComponent.new(pull_request: @pull), layout: component_fragment_layout
      end

      format.json do
        return render_404 unless conversations_react_enabled?

        render_rails_partial_payload(payload: conversation_body_payload(@pull))
      end
    end
  end

  def commit_status_icon # rubocop:todo GitHub/UseRestfulActions
    oid = params[:oid]
    return head :not_found unless oid

    commit = @pull.changed_commits.find { |commit| commit.oid == oid }
    return head :not_found unless commit
    return head :ok unless commit.has_status_check_rollup?

    respond_to do |format|
      format.html do
        render PullRequests::TimelineEvents::CommitStatusIconComponent.new(commit: commit, pull_request: @pull), layout: component_fragment_layout
      end
    end
  end

  def file_tree # rubocop:todo GitHub/UseRestfulActions
    pull_comparison = PullRequest::Comparison.find \
      pull: @pull,
      start_commit_oid: params[:start_commit_oid],
      end_commit_oid: params[:end_commit_oid],
      base_commit_oid: params[:base_commit_oid]
    return head :not_found unless pull_comparison

    user_reviewed_files = PullRequestUserReviews.new(@pull, current_user)
    default_hydro_payload = default_file_tree_hydro_payload \
      file_count: pull_comparison.diffs.changed_files,
      pull_request_id: @pull.id

    respond_to do |format|
      format.html do
        render PullRequests::FileTree::RootComponent.new(
          pull_comparison.diffs,
          codeowners: pull_comparison.codeowners,
          viewed_files: user_reviewed_files,
          default_hydro_payload: default_hydro_payload
        ), layout: component_fragment_layout
      end
    end
  end

  def processing_indicator # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.json do
        stale = @pull.stale?
        render json: {
          stale: stale,
          # Only run the expensive query if the pull is stale
          latest_unsynced_push_to_head_ref_at: stale ? @pull.latest_unsynced_push_to_head_ref&.pushed_at&.iso8601 : nil,
        }
      end
    end
  end

  protected

  def tab_specified?(tab_name)
    specified_tab.to_s == tab_name.to_s
  end
  helper_method :tab_specified?

  def specified_tab
    return @specified_tab if defined?(@specified_tab)
    params[:tab].presence || "discussion"
  end
  helper_method :specified_tab

  private

  def set_page_responsive
    @page_responsive = true
  end

  def no_cache
    expires_now
  end

  def find_pull_request
    @pull = PullRequest.with_number_and_repo(params[:id].to_i, current_repository)
    head :not_found unless @pull
  end

  def route_supports_advisory_workspaces?
    %w(discussion status commits files).include?(specified_tab) ||
      %w[unread_timeline title].include?(action_name)
  end

  # Override AbstractRepositoryController#defer_commit_badges? to
  # opt-in to deferred loading of commit signature badges.
  def defer_commit_badges?
    true
  end

  # Override AbstractRepositoryController#defer_status_check_rollups? to
  # opt-in to deferred loading of status check rollups
  def defer_status_check_rollups?
    true
  end

  # Private: Returns the target entity for user name display configuration.
  #
  # This method determines which entity's user name display settings should be used
  # when rendering user names in the pull request partials context. For pull request partials, we use
  # the repository's organization configuration if available.
  #
  # Returns an Organization or nil if the repository is not owned by an organization.
  def target_for_user_name_display_configuration
    current_repository.organization
  end

  def should_rate_limit_request?
    !logged_in?
  end
end
