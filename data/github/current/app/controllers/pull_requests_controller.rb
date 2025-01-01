# typed: true
# frozen_string_literal: true

require "react_payload"

# rubocop:todo GitHub/RailsControllerRenderLiteral

class PullRequestsController < AbstractRepositoryController
  # All other actions will be mapped to the pull_requests service
  map_to_service :checks_api, only: [:checks] # rubocop:todo GitHub/MapToService

  include ShowPartial, MarketplaceHelper,
    TimelineHelper, HydroHelper, GateRequestHelper, ConditionalAccessDependency, SiteHelper,
    ControllerMethods::Codespaces, PullRequests::FileTreeHelper, FileFilterHelper,
    ControllerMethods::PullRequests, ControllerMethods::CheckAnnotations, PullRequests::DiffContentLoadingHelper,
    ApplicationController::PartialRenderWithLayoutDependency, PullRequests::MergeboxHelper,
    PullRequests::NewFilesChangedHelper, PullRequests::PageTitleHelper, Commits::ReactPayloadDataDependency, BranchesHelper,
    ApplicationController::VerifiedFetchDependency, ActionView::Helpers::TextHelper, PullRequests::DatabaseSelection

  allow_verified_fetch only: [:files]

  helper :compare

  rescue_from_timeout_without_replay only: [:merge] do
    T.bind(self, PullRequestsController)

    GitHub.dogstats.increment("pull_requests.merge_timeout_rescued")

    orchestration = PullRequests::Orchestrations::Merge.active.find_by(pull_request_id: @pull&.id)
    orchestration&.end_orchestration(:failed, "merge timed out")

    render_update_content_json({
      merging: render_to_string(
        partial: "pull_requests/merging",
        object: @pull,
        formats: :html,
        locals: {
          merging_error: {
            form_target: "js-merge-branch-form",
            unretryable: false,
            title: "Merge attempt failed",
            message: ("Merge attempt timed out."),
          },
        },
      ),
    }, status: :gateway_timeout)
  end

  before_action :set_page_responsive
  before_action :all_color_mode_themes, only: [:checks]
  before_action :login_required, only: [:create, :comment, :merge_button, :dismiss_protip, :ready_for_review, :convert_to_draft, :change_base, :apply_suggestions, :run_action_required_workflows]
  before_action :login_required_redirect_for_public_repo, only: [:new]
  before_action :writable_repository_required,
    except: %w(
      changes_since_last_review
      checks
      cleanup
      code_menu_contents
      commits
      convert_to_draft
      diff
      files
      merge_button
      new
      open_with_menu
      patch
      ready_for_review
      show
      timeline_more_items
      undo_cleanup
    )
  before_action :check_for_empty_repository, only: [:create, :new]
  before_action :no_cache
  before_action :ensure_pull_head_pushable, only: [:cleanup, :undo_cleanup, :cleanup_codespaces]
  before_action :content_authorization_required, only: [:create, :merge, :apply_suggestions]
  skip_before_action :cap_pagination, unless: :robot?

  prepend_around_action :use_repository_cluster_replicas, only: [:create]

  around_action :record_stats, only: [:show, :files, :commits]

  layout "repository"
  javascript_bundle :codespaces
  javascript_bundle :diffs
  javascript_bundle :scanning, only: [:show, :files, :checks]
  javascript_bundle :"code-menu"
  javascript_bundle :"copilot-coding-agent-status"
  stylesheet_bundle :code
  stylesheet_bundle :"pull-requests"

  param_encoding :create, :base, "ASCII-8BIT"
  param_encoding :create, :head, "ASCII-8BIT"
  param_encoding :new, :range, "ASCII-8BIT"

  depends_on_clusters ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::SecurityProductsEnablement,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Spokes,
    ApplicationRecord::Iam,
    optional: false, only: [:files, :commits, :diff, :conversations_menu, :show_partial_comparison, :show_toc, :merge_button, :resolve_conflicts, :code_menu_contents, :checks, :timeline_more_items, :new, :open_with_menu, :changes_since_last_review, :patch]

  rate_limit_requests \
    only: [:patch],
    if: :patch_action_request_is_rate_limited?,
    key: :patch_action_rate_limit_key,
    max: GitHub::RateLimitedRequest::DEFAULT_RATE_LIMIT_MAX,
    ttl: GitHub::RateLimitedRequest::DEFAULT_RATE_LIMIT_TTL

  #      _              _
  #  ___| |_ ___  _ __ | |
  # / __| __/ _ \| '_ \| |
  # \__ \ || (_) | |_) |_|
  # |___/\__\___/| .__/(_)
  #              |_|
  # By adding a cluster to this list, you are asserting that the
  # Pull Request page should respond with a 500 error when that
  # cluster is unavailable. Those kinds of changes should not be
  # made without talking with the Pull Requests team first.
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
    optional: false, only: [:show]
  )

  depends_on_clusters ApplicationRecord::Ballast,
    ApplicationRecord::Copilot,
    ApplicationRecord::Memex,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Notify,
    ApplicationRecord::Iam,
    ApplicationRecord::RepositoriesActionsChecks,
    optional: true, only: [:show, :code_menu_contents]

  depends_on_clusters(
    ApplicationRecord::Billing,
    ApplicationRecord::Iam,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Permissions,
    ApplicationRecord::RepositoriesPushes,
    optional: false, only: [:files]
  )
  depends_on_clusters(
    ApplicationRecord::Ballast,
    ApplicationRecord::Copilot,
    ApplicationRecord::Memex,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Notify,
    ApplicationRecord::RepositoriesActionsChecks,
    optional: true, only: [:files]
  )

  depends_on_clusters ApplicationRecord::Iam,
    ApplicationRecord::Permissions,
    ApplicationRecord::RepositoriesActionsChecks,
    optional: false, only: [:commits]

  depends_on_clusters ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Copilot,
    ApplicationRecord::Memex, # repo header link count
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Notify,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::RepositoriesPushes,
    optional: true, only: [:commits]

  depends_on_clusters ApplicationRecord::Ballast,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    optional: false, only: [:diff]

  depends_on_clusters ApplicationRecord::Iam,
    ApplicationRecord::Mysql2,
    optional: false, only: [:conversations_menu]

  depends_on_clusters ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Copilot,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Memex,
    ApplicationRecord::RepositoriesActionsChecks,
    optional: true, only: [:conversations_menu]

  depends_on_clusters ApplicationRecord::Iam,
    ApplicationRecord::Mysql2,
    optional: false, only: [:show_partial_comparison]

  depends_on_clusters ApplicationRecord::Billing,
    ApplicationRecord::Copilot,
    ApplicationRecord::Memex,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Notify,
    ApplicationRecord::RepositoriesActionsChecks,
    optional: true, only: [:show_partial_comparison]

  depends_on_clusters ApplicationRecord::Iam,
    ApplicationRecord::Mysql2,
    optional: false, only: [:show_toc]

  depends_on_clusters ApplicationRecord::Ballast,
    ApplicationRecord::Copilot,
    ApplicationRecord::Memex,
    ApplicationRecord::Mysql5,
    ApplicationRecord::RepositoriesActionsChecks,
    optional: true, only: [:show_toc]

  depends_on_clusters ApplicationRecord::Memex,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Permissions,
    ApplicationRecord::RepositoriesActionsChecks,
    optional: false, only: [:merge_button]

  depends_on_clusters ApplicationRecord::Memex,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    optional: false, only: [:resolve_conflicts]

  depends_on_clusters ApplicationRecord::Copilot,
    optional: true, only: [:resolve_conflicts]

  depends_on_clusters ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    optional: false, only: [:code_menu_contents]

  depends_on_clusters ApplicationRecord::Iam,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Permissions,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::RepositoriesPushes,
    optional: false, only: [:checks]

  depends_on_clusters ApplicationRecord::Ballast,
    ApplicationRecord::Memex,
    ApplicationRecord::Copilot,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Notify,
    optional: true, only: [:checks]

  depends_on_clusters ApplicationRecord::Mysql5,
    optional: false, only: [:changes_since_last_review, :patch]

  depends_on_clusters ApplicationRecord::Ballast,
    ApplicationRecord::Iam,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Permissions,
    optional: false, only: [:timeline_more_items]

  depends_on_clusters ApplicationRecord::Copilot,
    ApplicationRecord::Memex,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Notify,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::NotificationsEntries,
    optional: true, only: [:timeline_more_items]

  depends_on_clusters ApplicationRecord::RepositoriesActionsChecks,
    optional: false, only: [:new]

  depends_on_clusters ApplicationRecord::Ballast,
    ApplicationRecord::Memex,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    optional: true, only: [:new]

  depends_on_clusters ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Iam,
    optional: false, only: [:open_with_menu]

  depends_on_clusters ApplicationRecord::Billing,
    ApplicationRecord::Mysql5,
    optional: true, only: [:open_with_menu]

  depends_on_clusters ApplicationRecord::Copilot,
    optional: true, only: [:open_with_menu]

  depends_on_clusters ApplicationRecord::Collab,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    optional: false, only: [:deferred_commits_data]

  depends_on_clusters ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Spokes,
    optional: true, only: [:deferred_commits_data]

  depends_on_clusters(
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Permissions,
    ApplicationRecord::Repositories,
    optional: false,
    only: [:post_merge]
  )
  depends_on_clusters(
    ApplicationRecord::Copilot,
    ApplicationRecord::Memex,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Notify,
    ApplicationRecord::NotificationsSummaries,
    ApplicationRecord::RepositoriesActionsChecks,
    optional: true,
    only: [:post_merge]
  )

  SHOW_FEATURES = [
    :new_merge_box_ga_bypass_override,
    :auto_merge,
    :benchmark_mergebox,
    :cap_two_factor_filter,
    :copilot_coding_guidelines,
    :mergebox_react_partial,
    :merge_queue,
    :merge_queue_extra_branch_protection_settings,
    :new_merge_box_ga,
    :previewable_form_component,
    :read_from_merge_box_json_api,
    :slash_commands,
    :notifications_async_issues_subscription_button,
    :display_comment_actions,
    :may_post_comment_actions,
  ].freeze

  COMMITS_TO_FETCH_DATA_FOR_AT_A_TIME = 10

  preload_features SHOW_FEATURES, only: :show
  preload_features [:prx_files, :prx_files_ssr, :react_diff_line_type_character_correction, :apply_prx_limits], only: :files

  def new
    if GitHub.flipper[:pull_request_templates].enabled?(current_user) || GitHub.flipper[:pull_request_templates].enabled?(current_repository)
      safe_redirect_to compare_path(current_repository, params[:range])
    else
      safe_redirect_to compare_path(current_repository, params[:range], expand: true)
    end
  end

  def create
    repo = current_repository
    return render_404 unless repo
    return if reject_bully?
    GitHub.context.push(spamurai_form_signals: spamurai_form_signals)

    unsafe_params = T::unsafe(params).permit!.to_h.with_indifferent_access
    unsafe_pull_request_params = unsafe_params[:pull_request]

    issue = build_issue unsafe_params

    if issue.present?
      issue.title = unsafe_pull_request_params[:title] unless issue.title.present?
      issue.body = unsafe_pull_request_params[:body] unless issue.body.present?
    end

    options = unsafe_params.slice :base, :head
    options[:user] = current_user
    options[:issue] = issue
    options[:collab_privs] = !!unsafe_params[:collab_privs]
    options[:reviewer_user_ids] = unsafe_params[:reviewer_user_ids]
    options[:reviewer_team_ids] = unsafe_params[:reviewer_team_ids]
    options[:issue_memex_project_ids] = unsafe_params[:issue_memex_project_ids]

    options[:draft] = unsafe_params[:draft] == "on"
    PullRequests::UserSettings.new(current_user, repo).set_default_pull_requests_to_draft(options[:draft])

    if unsafe_params[:head_repo].present?
      head_repo = Repository.with_name_with_owner(unsafe_params[:head]&.split(":")&.first, params[:head_repo])
      if head_repo && current_repository.id != head_repo.id && current_repository.source_id == head_repo.source_id
        options[:head_repo] = head_repo if head_repo.readable_by?(current_user)
      end
    end

    begin
      @pull_request = PullRequest.create_for!(repo, options)
      @issue        = @pull_request.issue

      begin
        track_time(tags: ["method:create", "step:add_to_memex_projects"]) do
          @issue.add_to_memex_projects!(
            options[:issue_memex_project_ids],
            @pull_request,
            options[:user]
          )
        end
      rescue GitHub::Prioritizable::Context::LockedForRebalance, GitHub::Prioritizable::RebalanceRequiredError
        selected_project_count = (params[:issue_memex_project_ids] || {}).values.count { |v| v == "on" }
        GitHub.dogstats.increment("memex_project_items.exceptions.locked_for_rebalance", { tags: ["context:pull_requests_controller.create"] })
        flash[:error] = "Sorry! We encountered an error and the pull request was not added to the selected #{"project".pluralize(selected_project_count)}. Please try again."
      rescue MemexProjectItem::ProjectLimitReachedError => error
        GitHub.dogstats.increment("memex_project_items.exceptions.project_limit_reached", { tags: ["context:pull_requests_controller.create"] })
        projects_with_errors_count = error.memex_projects_with_errors.count
        flash[:error] = "Sorry! We were unable to add the pull request to the selected #{"project".pluralize(projects_with_errors_count)}. Projects cannot have more than #{error.memex_projects_with_errors.first&.items_limit} items."
      end

      if params[:show_onboarding_guide_tip].present?
        next_url = pull_request_path(@pull_request, repo)
        redirect_to "#{next_url}?show_onboarding_guide_tip=true"
        return
      end

      redirect_to pull_request_path(@pull_request, repo)
    rescue ActiveRecord::RecordInvalid => e
      flash[:error] = "Pull request creation failed. #{human_failure_message(e)}"
      range = [options[:base], options[:head]].compact.join("...")
      redirect_to compare_path(repo, range, expand: true)
    end
  end

  def files # rubocop:todo GitHub/UseRestfulActions
    unsafe_params = T::unsafe(params).permit!.to_h.with_indifferent_access

    redirect_or_error = ensure_valid_pull_request

    if performed?
      return redirect_or_error
    end

    range = unsafe_params[:range]
    return render_pull_requests_react(@pull, range) if new_files_changed_feature_enabled_for_user?(current_user, params)

    stats.entity = @pull

    set_hovercard_subject(@pull)

    if range
      env["pull_request.timeout_reason"] = "compute_diff"

      oid1, oid2 = parse_show_range_oid_components!(@pull, range)

      expected_canonical_range = oid1 ? "#{oid1}..#{oid2}" : "#{oid2}"
      if range != expected_canonical_range
        return redirect_to(range: expected_canonical_range)
      end

      @comparison = @pull.historical_comparison
      merge_base_oid = @comparison.compare_repository.best_merge_base(@pull.base_sha, oid2)

      if merge_base_oid.nil?
        return render "pull_requests/orphan_commit", status: :not_found, locals: { oid2: oid2 }
      end

      oid1 ||= @pull.compare_repository.best_merge_base(oid2, merge_base_oid) if merge_base_oid
      unless @pull_comparison = PullRequest::Comparison.find(pull: @pull, start_commit_oid: oid1, end_commit_oid: oid2, base_commit_oid: merge_base_oid, viewer: current_user)
        raise BadRange
      end

      load_diff

      env["pull_request.timeout_reason"] = nil
    else
      @comparison = @pull.comparison

      return if pjax? && !stale?(@pull, template: false)

      env["pull_request.timeout_reason"] = "compute_diff"

      start_oid, end_oid = @pull.merge_base, @pull.head_sha
      if start_oid && end_oid
        begin
          start_commit, end_commit = @pull.compare_repository.commits.find([start_oid, end_oid])
          @pull_comparison = PullRequest::Comparison.new(pull: @pull, start_commit: start_commit, end_commit: end_commit, base_commit: start_commit, viewer: current_user)

          load_diff
        rescue GitRPC::ObjectMissing
        end

        env["pull_request.timeout_reason"] = nil
      end
    end

    if @pull_comparison && logged_in?
      async_mark_comparison_as_seen(@pull_comparison, user: current_user)
      mark_pull_notification_as_read @pull.issue
    end

    stats.record_distribution("prepare_and_highlight") do
      prepare_for_rendering_files(pull_comparison: @pull_comparison)
    end

    override_analytics_location "/<user-name>/<repo-name>/pull_requests/show/files"

    respond_to do |format|
      format.html do
        if logged_in?
          @current_review = @pull.latest_pending_review_for(current_user)
        end

        if @pull_comparison.nil?
          render "pull_requests/files_unavailable"
        else
          file_count = @pull_comparison.diffs.changed_files
          file_tree_available = file_tree_available?(
            file_count: file_count,
          )

          render "pull_requests/files", locals: {
            show_checks_status: GitHub.actions_enabled?,
            file_count: file_count,
            file_tree_available: file_tree_available,
            visibility: codespaces_menu_visibility
          }
        end
      end
    end
  rescue GitHub::Diff::Parser::UnrecognizedText => error
    render "pull_requests/unrecognized_diff_text", status: :not_found, locals: { pull: @pull }
  rescue BadRange
    disable_account_switcher_popover
    render "pull_requests/bad_range", status: :not_found
  end

  def checks # rubocop:todo GitHub/UseRestfulActions
    unsafe_params = T::unsafe(params).permit!.to_h.with_indifferent_access

    redirect_or_error = ensure_valid_pull_request

    if performed?
      return redirect_or_error
    end

    set_hovercard_subject(@pull)

    override_analytics_location "/<user-name>/<repo-name>/pull_requests/show/checks"

    respond_to do |format|
      format.html do
        selected_check_run = Checks.domain.check_runs.for_id(unsafe_params[:check_run_id].to_i, repository_id: current_repository.id) if unsafe_params[:check_run_id]

        if unsafe_params[:check_run_id] && !@pull.changed_commit_oids.include?(selected_check_run&.head_sha)
          flash[:notice] = "No check run found with ID #{unsafe_params[:check_run_id]} for this pull request."
          redirect_to "#{pull_request_path(@pull)}/checks" and return
        end

        if selected_check_run || params[:sha]
          sha = selected_check_run&.head_sha || params[:sha]
          commit = @pull.changed_commits.find { |commit| commit.oid == sha }

          unless commit
            flash[:notice] = "No commit was found with sha #{sha} for this pull request."
            redirect_to "#{pull_request_path(@pull)}/checks" and return
          end
        else
          sha = @pull.head_sha
          commit = @pull.changed_commits.find { |commit| commit.oid == sha }
        end

        check_suites = @pull.matching_check_suites(head_sha: sha)
        selected_check_run ||= if check_suite = T.let(check_suites.first, T.nilable(CheckSuite))
          Checks.domain.check_runs.first_for_check_suite(check_suite)
        end

        if selected_check_run
          annotation_details = load_annotation_details(check_run: selected_check_run)
        end

        commit_check_runs = if commit.nil?
          []
        else
          CheckRun.for_sha_and_repository_id_with_limit(current_repository.id, commit.oid, CheckRun.default_max_check_suites_per_sha_limit)
        end

        render "checks/show", locals: {
          commit: commit,
          selected_check_run: selected_check_run,
          check_suites: check_suites,
          blankslate: show_blankslate?(check_suites, selected_check_run, current_repository),
          workflows_loading: workflows_loading?(check_suites, selected_check_run),
          annotation_details: annotation_details,
          commit_check_runs: commit_check_runs,
          pull: @pull
        }
      end
    end
  end

  def timeline_more_items # rubocop:todo GitHub/UseRestfulActions
    redirect_or_error = ensure_valid_pull_request
    if performed?
      return redirect_or_error
    end

    return render_404 unless valid_cursors?(params[:before_cursor], params[:after_cursor])

    timeline_owner = PullRequest::ShowLoader.issue_node(
      @pull,
      current_repository,
      current_user,
      cap_filter: cap_filter,
      pagination_params: {
        exclude_item_types: exclude_item_types,
        per_page: params[:timeline_per_page] || DEFAULT_PAGE_SIZE,
        before_cursor: params[:before_cursor],
        after_cursor: params[:after_cursor]
      }
    )

    render PullRequests::PagedTimelineComponent.new(timeline_owner: timeline_owner), layout: component_fragment_layout
  end

  def show
    unsafe_params = T::unsafe(params).permit!.to_h.with_indifferent_access

    redirect_or_error = ensure_valid_pull_request

    if performed?
      return redirect_or_error
    end

    stats.entity = @pull

    set_hovercard_subject(@pull)

    mark_pull_notification_as_read @pull.issue

    respond_to do |format|
      format.html do
        pull_node = stats.record_distribution("fetch_data", include_net: true) do
          pagination_params = { exclude_item_types: exclude_item_types, per_page: params[:timeline_per_page] }
          PullRequest::ShowLoader.issue_node(@pull, current_repository, current_user, cap_filter: cap_filter, pagination_params: pagination_params)
        end

        stats.record_distribution("render_content") do
          render "pull_requests/conversation", locals: {
            pull_node: pull_node,
            pull_request: @pull,
            gate_requests: gate_requests_for(pull_request: @pull, user: current_user)
          }
        end
      end

      # At the moment, nothing within the product will request layout data from this
      # endpoint, but for completeness we're responding to the request for JSON.
      # If we ever add a cache time to the query or otherwise invalidate the query data on the
      # client, we'll need to make a direct request to this route.
      format.json do
        header_data = PullRequests::PageData::HeaderPayload.build(
          current_user:,
          pull_request: @pull,
        )
        render_react_json(payload: PullRequestsLayoutPayload.new(header_data))
      end
    end
  end

  def commits # rubocop:todo GitHub/UseRestfulActions
    unsafe_params = T::unsafe(params).permit!.to_h.with_indifferent_access

    redirect_or_error = ensure_valid_pull_request

    stats.entity = @pull

    if performed?
      return redirect_or_error
    end

    set_hovercard_subject(@pull)

    commit_file_view = false

    range = unsafe_params[:range]
    if range
      env["pull_request.timeout_reason"] = "compute_diff"

      oid1, oid2 = parse_show_range_oid_components!(@pull, unsafe_params[:range])

      expected_canonical_range = oid1 ? "#{oid1}..#{oid2}" : "#{oid2}"
      if unsafe_params[:range] != expected_canonical_range
        return redirect_to(range: expected_canonical_range)
      end

      commit_file_view = true
      oid1 = current_repository.commits.find(oid2).parent_oids.first

      @comparison = @pull.historical_comparison
      merge_base_oid = @comparison.compare_repository.best_merge_base(@pull.base_sha, oid2)

      if merge_base_oid.nil?
        return render "pull_requests/orphan_commit", status: :not_found, locals: { oid2: oid2 }
      end

      oid1 ||= @pull.compare_repository.best_merge_base(oid2, merge_base_oid) if merge_base_oid
      unless @pull_comparison = PullRequest::Comparison.find(pull: @pull, start_commit_oid: oid1, end_commit_oid: oid2, base_commit_oid: merge_base_oid)
        raise BadRange
      end

      load_diff

      env["pull_request.timeout_reason"] = nil
    else
      @comparison = @pull.comparison
    end

    if commit_file_view && @pull_comparison && logged_in?
      async_mark_comparison_as_seen(@pull_comparison, user: current_user)
      mark_pull_notification_as_read @pull.issue
    end

    if commit_file_view
      prepare_for_rendering_files(pull_comparison: @pull_comparison)
    end

    override_analytics_location "/<user-name>/<repo-name>/pull_requests/show/commits"

    respond_to do |format|
      format.html do
        if commit_file_view
          if logged_in?
            @current_review = @pull.latest_pending_review_for(current_user)
          end

          if @pull_comparison.nil?
            render "pull_requests/files_unavailable"
          else
            file_count = @pull_comparison.diffs.changed_files
            render "pull_requests/files", locals: {
              show_checks_status: GitHub.actions_enabled?,
              file_count: file_count,
              file_tree_available: file_tree_available?(file_count: file_count),
              visibility: codespaces_menu_visibility
            }
          end
        else
          render_pull_requests_react(@pull, range)
        end
      end

      format.json do
        render_pull_requests_react(@pull, range)
      end

      format.diff { redirect_to commit_path(oid2, current_repository) + ".diff" }
      format.patch { redirect_to commit_path(oid2, current_repository) + ".patch" }
    end
  rescue BadRange
    disable_account_switcher_popover
    render "pull_requests/bad_range", status: :not_found
  end

  def open_with_menu # rubocop:todo GitHub/UseRestfulActions
    redirect_or_error = ensure_valid_pull_request
    return redirect_or_error if performed?

    render Codespaces::CodeMenuDropdownComponent.new(
      visibility: codespaces_menu_visibility,
      repository: current_repository,
      pull_request: @pull,
      ref: params[:ref]
    ), layout: component_fragment_layout
  end

  def code_menu_contents # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless T.must(request).xhr?

    redirect_or_error = ensure_valid_pull_request
    return redirect_or_error if performed?

    render Codespaces::CodeMenuContentsComponent.new(
      visibility: codespaces_menu_visibility,
      pull_request: @pull,
      repository: current_repository,
    ), layout: component_fragment_layout
  end

  def changes_since_last_review # rubocop:todo GitHub/UseRestfulActions
    redirect_or_error = ensure_valid_pull_request
    return redirect_or_error if performed?

    unless logged_in?
      return redirect_to pull_request_diff_range_path(@pull)
    end

    unless most_recent_review = @pull.latest_non_pending_review_for(current_user)
      return redirect_to pull_request_diff_range_path(@pull)
    end

    unless most_recent_review.pull_request_has_changed? && most_recent_review.applies_to_current_diff?
      return redirect_to pull_request_diff_range_path(@pull)
    end

    redirect_to pull_request_diff_range_path(@pull, range: [most_recent_review.head_sha, "HEAD"])
  end

  def show_partial_comparison # rubocop:todo GitHub/UseRestfulActions
    raise "Unexpected partial in params: #{params[:partial]}" unless params[:partial] == "pull_requests/stale_comparison"

    unless pull = PullRequest.with_number_and_repo(params[:id].to_i, current_repository)
      return head :not_found
    end

    unless pull_comparison = PullRequest::Comparison.find(pull: pull, start_commit_oid: params[:start_commit_oid], end_commit_oid: params[:end_commit_oid], base_commit_oid: params[:base_commit_oid])
      return head :not_found
    end

    GitHub.dogstats.time("view", tags: ["subject:pull_request", "action:show_partial_render"]) do
      respond_to do |format|
        format.html do
          render partial: "pull_requests/stale_comparison", layout: partial_fragment_layout, locals: { pull: pull, pull_comparison: pull_comparison }
        end
      end
    end
  end

  def show_toc # rubocop:todo GitHub/UseRestfulActions
    pull = PullRequest.with_number_and_repo(params[:id], current_repository)
    return head :not_found unless pull

    return head :not_found unless valid_sha_param?(:sha1) &&
                                  valid_sha_param?(:sha2) && params[:sha2].present? &&
                                  valid_sha_param?(:base_sha)

    diff_options = {
      base_sha: params[:base_sha],
      base_repository: pull.base_repository,
      head_repository: pull.head_repository,
    }
    diff = GitHub::Diff.new(pull.compare_repository, params[:sha1], params[:sha2], diff_options)

    respond_to do |format|
      format.html do
        render partial: "pull_requests/diffbar/toc_menu_items",
          layout: partial_fragment_layout,
          locals: {
            summary_delta_views: diff.summary.deltas.map { |d| ::Diff::SummaryDeltaView.new(d) }
          }
      end
    end
  end

  def conversations_menu # rubocop:todo GitHub/UseRestfulActions
    pull = PullRequest.with_number_and_repo(params[:id], current_repository)
    return head :not_found unless pull

    threads = PullRequestReviewThread.where(pull_request_id: pull.id)
      .joins(:pull_request_review)
      .where.not(pull_request_review: { state: PullRequestReview.state_value(:pending) })
      .order(created_at: :desc)
      .includes(:review_comments)

    threads = threads.filter(&:conversation?)

    unresolved_threads, resolved_threads = threads.partition { |thread| thread.resolver_id.nil? }

    if params[:instrument] == "1"
      GlobalInstrumenter.instrument("pull_request.user_action",
        {
          user_id: current_user&.id,
          pull_request_id: pull.id,
          category: "conversations_menu",
          action: "opened",
          data: {
            unresolved_threads_count: unresolved_threads.length,
            resolved_threads_count: resolved_threads.length,
            unresolved_threads_ids: unresolved_threads.map { |thread| thread.id },
            resolved_threads_ids: resolved_threads.map { |thread| thread.id },
            outdated_threads: unresolved_threads.count { |t| t.outdated? } + resolved_threads.count { |t| t.outdated? },
          }
        }
      )
    end

    respond_to do |format|
      format.html do
        render partial: "pull_requests/diffbar/conversations_menu",
          layout: partial_fragment_layout,
          locals: {
            unresolved_threads: unresolved_threads,
            resolved_threads: resolved_threads,
            pull_request_id: pull.id,
          }
      end
    end
  end

  def cleanup # rubocop:todo GitHub/UseRestfulActions
    # The branch was deleted by someone else before this user
    # clicked the button. Send us to the bottom.
    if !@pull.head_ref_exist?
      raise Git::Ref::NotFound
    end

    result = @pull.cleanup_head_ref(current_user,
                              reflog_data: request_reflog_data("pull request branch delete button"))

    GitHub.dogstats.increment("pull_request", tags: ["action:cleanup", "#{result ? "result:success" : "error:invalid"}"])

    if T.must(request).xhr?
      status = result ? :ok : :unprocessable_entity
      render_head_ref_update(status: status)
    else
      if result
        flash[:notice] = "Branch deleted successfully."
      else
        flash[:error] = "Oops, something went wrong."
      end

      redirect_to pull_request_path(@pull)
    end

  # We can get here both from above where the branch has already
  # been deleted before the button is clicked, or a race condition
  # where the application code thinks the branch exists but by
  # the time we execute the git command, someone else has already deleted it.
  rescue Git::Ref::NotFound
    GitHub.dogstats.increment("pull_request", tags: ["action:cleanup", "error:already_deleted"])
    render_head_ref_update(status: :unprocessable_entity, unretryable: true)
  end

  def undo_cleanup # rubocop:todo GitHub/UseRestfulActions
    stats_key = @pull.cross_repo? ? "cross_repo" : "same_repo"

    status = :ok
    if @pull.restore_head_ref(current_user,
                              request_reflog_data("pull request branch undo button"))
      GitHub.dogstats.increment("pull_request", tags: ["action:undo_cleanup", "result:success", "repo:#{stats_key}"])
    else
      status = :unprocessable_entity
      GitHub.dogstats.increment("pull_request", tags: ["action:undo_cleanup", "error:invalid", "repo:#{stats_key}"])
    end

    render_head_ref_update(status: status, unretryable: true)
  end

  def cleanup_codespaces # rubocop:todo GitHub/UseRestfulActions
    codespaces = @pull.codespaces.can_be_deprovisioned_by_user(current_user)

    result = codespaces.all? do |codespace|
      codespace.deprovision!(reason: Codespace.deletion_reasons[:user_requested])
    end

    GitHub.dogstats.increment("codespaces.merge_merge_cleanup ", tags: ["#{result ? "result:success" : "error:invalid"}"])

    if T.must(request).xhr?
      status = result ? :ok : :unprocessable_entity
      render_head_ref_update(status: status)
    else
      if result
        flash[:notice] = "#{'Codespace'.pluralize(codespaces.size)} deleted successfully."
      else
        flash[:error] = "Some codespaces could not be deleted"
      end

      redirect_to pull_request_path(@pull)
    end
  end

  def merge # rubocop:todo GitHub/UseRestfulActions
    @pull = current_repository.issues.find_by_number(params[:id].to_i).try(:pull_request) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    return render_404 unless @pull

    allowable_merge_methods = @pull.async_allowable_merge_methods(actor: current_user).sync

    if params[:squash_commits] == "1"
      merge_method = "squash"
    elsif params[:do].present?
      merge_method = params[:do]
    else
      if allowable_merge_methods.merge_commit.allowed?
        merge_method = "merge"
      else
        merge_method = "squash"
      end
    end

    merge_method_setting = case merge_method
    when "merge"
      allowable_merge_methods.merge_commit
    when "squash"
      allowable_merge_methods.squash_merge
    when "rebase"
      allowable_merge_methods.rebase_merge
    else
      PullRequest::MergeMethodSettings::Value::Disallowed
    end

    if merge_method_setting.error?
      result, message = nil, "Failed to load repository settings. Please wait a few minutes and then try again."
    elsif merge_method_setting.disallowed?
      result, message = nil, "The selected merge method (#{merge_method}) is not allowed."
    elsif invalid_author_email?(params[:author_email])
      result, message = nil, "Invalid email for web commit."
    elsif @pull.git_merges_cleanly? && @pull.base_repository.pushable_by?(current_user)
      GitHub.dogstats.increment("pull_request", tags: ["action:merge"])

      merge_action = params[:admin_override] ? :admin_override_merge : :direct_merge

      begin
        case merge_result = PullRequests::Merge.call(
          pull_request: @pull,
          user: T.must(current_user),
          commit_title: params[:commit_title],
          commit_body: params[:commit_message],
          commit_author_email: params[:author_email],
          reflog_data: request_reflog_data("pull request merge button"),
          expected_head_sha: params[:head_sha],
          method: merge_method.to_sym,
          source: merge_action
        )
        when PullRequests::Merge::Success
          result, message = true, nil
        when PullRequests::Merge::Failure
          result, message = nil, merge_result.error_message
        else
          T.absurd(merge_result)
        end
      rescue Git::Ref::HookFailed => e
        @hook_out = e.message.force_encoding("UTF-8").scrub!
        result, message = nil, "Merging was blocked by pre-receive hooks."
      end

      begin
        if merge_method == "rebase"
          @pull.base_repository.set_sticky_merge_method(current_user, "rebase")
        elsif merge_method == "squash"
          @pull.base_repository.set_sticky_merge_method(current_user, "squash")
        elsif merge_method == "merge"
          @pull.base_repository.set_sticky_merge_method(current_user, "merge_commit")
        end
      rescue => e # rubocop:disable Lint/GenericRescue
        Failbot.report(e)
      end
    else
      result, message = nil, "We couldn’t merge this pull request. Reload the page before trying again."
    end

    if T.must(request).xhr?
      if result
        GitHub.dogstats.histogram("pull_request.merged.requested_reviewers.count", @pull.review_requests.pending.size)
        query_params = {
          timeline_per_page: params[:timeline_per_page],
          since: params[:since],
        }.compact

        redirect_to pull_request_post_merge_path(
          current_repository.owner_display_login,
          current_repository.name,
          @pull.number,
          format: :json,
          **query_params
        )
      else
        GitHub.dogstats.increment("pull_request", tags: ["action:merge", "error:invalid"])
        respond_to do |format|
          format.json do
            render_update_content_json({
              merging: render_to_string(
                partial: "pull_requests/merging",
                object: @pull,
                formats: :html,
                locals: {
                  merging_error: {
                    form_target: "js-merge-branch-form",
                    unretryable: !@pull.currently_mergeable?,
                    title: "Merge attempt failed",
                    message:,
                    hook_output: @hook_out,
                  },
                },
              ),
            }, status: :unprocessable_entity)
          end
        end
      end
    else
      if result
        GitHub.dogstats.histogram("pull_request.merged.requested_reviewers.count", @pull.review_requests.pending.size)
        redirect_to pull_request_path(@pull) + "#merged-event"
      else
        flash[:error] = message
        GitHub.dogstats.increment("pull_request", tags: ["action:merge", "error:invalid"])
        redirect_to pull_request_path(@pull)
      end
    end
  end

  # A successful merge XHR will redirect here to render updates.
  # We do not render in the `#merge` action to reduce the likelihood of
  # timeouts, and to avoid sending SELECT queries to cluster primaries.
  def post_merge # rubocop:todo GitHub/UseRestfulActions
    @pull = current_repository.issues.find_by_number(params[:id].to_i).try(:pull_request) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    return render_404 unless @pull

    pull_node = PullRequest::ShowLoader.issue_node(
      @pull,
      current_repository,
      current_user,
      cap_filter:,
      pagination_params: {
        per_page: params[:timeline_per_page],
        timeline_since: helpers.discussion_last_modified_at&.iso8601,
      },
    )

    respond_to do |format|
      # The `format.json` block must stay at the top here if any format
      # block is added in future, so that when the `Accept` header is `*/*`
      # we will continue to send JSON by default.
      format.json do
        render_update_content_json({
          timeline: render_to_string(
            partial: "pull_requests/timeline",
            object: @pull,
            formats: :html,
            locals: {
              pull_node: pull_node,
            },
          ),
          sidebar: render_to_string(
            partial: "pull_requests/sidebar",
            object: @pull,
            formats: :html,
            locals: {
              pull_node: pull_node,
              pull: @pull,
            },
          ),
          merging: render_to_string(
            partial: "pull_requests/merging",
            object: @pull,
            formats: :html,
          ),
          form_actions: render_to_string(
            partial: "pull_requests/form_actions",
            object: @pull,
            formats: :html,
            locals: {
              pull: @pull,
              issue_node: pull_node,
            },
          ),
          pull_request_tab_count: render_to_string(
            partial: "navigation/repository/tab_counter",
            formats: :html,
            locals: {
              count: current_repository.open_pull_request_count_for(current_user), # domain-isolation-query-violation:ignore:packages/issues (SELECT)
              label: "Pull requests"
            }
          ),
        })
      end
    end
  end

  def change_base # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless params[:new_base_binary]

    @pull = find_pull_request
    return render_404 unless @pull && @pull.issue.can_modify?(current_user)

    new_base = Base64.decode64(params[:new_base_binary])
    unless new_base.present?
      return redirect_to pull_request_path(@pull), flash: { error: "Please select a base branch." }
    end

    if T.must(request).xhr?
      change_branch_async
    else
      begin
        @pull.change_base_branch(current_user, new_base)
        flash[:notice] = "Updated base branch to #{new_base}."
      rescue PullRequest::BaseNotChangeableError => e
        flash[:error] = e.ui_message
      end
      redirect_to pull_request_path(@pull)
    end
  end

  def update_branch # rubocop:todo GitHub/UseRestfulActions
    @pull = find_pull_request
    return render_404 unless @pull

    update_method = params[:update_method] == "rebase" ? "rebase" : "merge"
    result = PullRequests::UpdateBranch.execute(pull_request: @pull, user: T.must(current_user), update_method:, expected_head_oid: params[:expected_head_oid])

    case result
    when PullRequests::UpdateBranch::Success
      render json: { orchestration: { url: pull_request_orchestration_status_url(orchestration_id: result.orchestration.id) } }
    when PullRequests::UpdateBranch::Error
      render json: { error_message: result.error_message }, status: :unprocessable_entity
    else
      T.absurd(result)
    end
  end

  def revert # rubocop:todo GitHub/UseRestfulActions
    @pull = find_pull_request
    return render_404 unless @pull && @pull.revertable_by?(current_user)

    stats_key = @pull.cross_repo? ? "cross_repo" : "same_repo"

    begin
      revert_branch, error = @pull.revert(current_user, request_reflog_data("pull request revert button"), timeout: (request_time_left / 3))
      if revert_branch
        GitHub.dogstats.increment("pull_request", tags: ["action:revert", "repo:#{stats_key}"])

        base_label, head_label =
          if revert_branch.repository == @pull.base_repository
            [@pull.base_ref_name, revert_branch.name]
          else
            ["#{@pull.base_label(username_qualified: true)}", "#{revert_branch.repository.owner.display_login}:#{revert_branch.name}"]
          end

        flash[:pull_request] = {
          title: "Revert \"#{@pull.title}\"",
          body: "Reverts #{@pull.base_repository.name_with_display_owner}##{@pull.number}",
        }
        redirect_to(compare_path(@pull.base_repository, "#{base_label}...#{head_label}", expand: true))
      else
        if error == :merge_conflict
          GitHub.dogstats.increment("pull_request", tags: ["action:revert", "error:merge_conflict"])
        else
          GitHub.dogstats.increment("pull_request", tags: ["action:revert", "error:invalid"])
        end

        flash[:error] = "Sorry, this pull request couldn’t be reverted automatically. It may have \
                         already been reverted, or the content may have changed since it was merged."
        redirect_to pull_request_path(@pull)
      end
    rescue Git::Ref::HookFailed => e
      flash[:hook_out] = e.message
      flash[:hook_message] = "Pull request could not be reverted."
      redirect_to pull_request_path(@pull)
    rescue Git::Ref::RepositoryRuleViolationError => e
      logger_params = {
        "gh.pull_request.id": @pull.id,
        "gh.pull_request.action": "revert",
        "gh.pull_request.error_details": e.detailed_message
      }

      GitHub.logger.error("failed to revert pull request", logger_params)
      Failbot.report(e, logger_params)

      flash[:revert_error_heading] = e.message
      flash[:revert_error_details] = e.failed_runs.map(&:message).join("\n\n")
      redirect_to pull_request_path(@pull)
    end
  end

  def merge_button # rubocop:todo GitHub/UseRestfulActions
    pull = PullRequest.with_number_and_repo(params[:id].to_i, current_repository, include: [:auto_merge_request])

    return render_404 if pull.nil?
    merge_state = pull.cached_merge_state(viewer: current_user)

    # explicitly force firing off the merge commit job if needed
    pull.enqueue_mergeable_update(priority: :high)

    if pull.auto_merge_request
      GitHub.instrument(
        "pull_requests_controller.merge_button",
        pull_request_id: pull.id,
        actor_id: T.must(current_user).id,
        repo_id: current_repository.id,
        merge_state: merge_state.status,
        auto_merge_error: pull.auto_merge_request.merge_error
      )
    end

    respond_to do |format|
      format.html do
        if merge_state.unknown?
          head :accepted
        else
          render partial: "pull_requests/merge_button", locals: { pull: pull }
        end
      end

      format.json do
        render json: { mergeable_state: merge_state.status }.to_json
      end
    end
  end

  def diff # rubocop:todo GitHub/UseRestfulActions
    # This might be a request for a redirect to the PR for a branch name ending in .diff,
    # or might be a request for a numbered PR in .diff format.
    diff_ref = "#{params[:id]}.diff"
    if current_repository.heads.include?(diff_ref)
      return redirect_or_404(diff_ref)
    end

    redirect_or_error = ensure_valid_pull_request
    if performed?
      redirect_or_error
    else
      redirect_to build_pull_request_diff_url
    end
  end

  def patch # rubocop:todo GitHub/UseRestfulActions
    # This might be a request for a redirect to the PR for a branch name ending in .patch,
    # or might be a request for a numbered PR in .patch format.
    patch_ref = "#{params[:id]}.patch"
    if current_repository.heads.include?(patch_ref)
      return redirect_or_404(patch_ref)
    end

    redirect_or_error = ensure_valid_pull_request
    if performed?
      redirect_or_error
    else
      redirect_to build_pull_request_patch_url
    end
  end

  def comment # rubocop:todo GitHub/UseRestfulActions
    @pull = current_repository.issues.find_by_number(params[:id].to_i).try(:pull_request) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    return if reject_bully?(@pull)
    return render_404 unless @pull
    issue = @pull.issue

    valid = true
    comment_body = params[:comment][:body]

    if !comment_body.nil? && !can_skip_creating_comment?
      comment = issue.create_comment(current_user, comment_body) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      valid &&= comment.persisted?

    elsif params[:comment_and_close] == "1"
      comment = issue.comment_and_close(current_user, comment_body) # domain-isolation-query-violation:ignore:packages/issues (SELECT, UPDATE)
      valid &= comment if comment_body.present?

      GitHub.dogstats.increment("pull_request.closed", tags: ["with_comment:#{comment_body.present?}"])
      GitHub.dogstats.histogram("pull_request.closed.requested_reviewers.count", @pull.review_requests.pending.size)

    elsif params[:comment_and_open] == "1"
      comment = issue.comment_and_open(current_user, comment_body) # domain-isolation-query-violation:ignore:packages/issues (SELECT, UPDATE)
      valid &= comment if comment_body.present?
    end

    mark_pull_notification_as_read issue
    if valid && comment_body.present?
      GitHub.instrument "comment.create", user: current_user
      instrument_saved_reply_use(params[:saved_reply_id], "pull_request_comment")
    end

    respond_to do |format|
      # The `format.json` block must stay at the top here if any format
      # block is added in future, so that when the `Accept` header is `*/*`
      # we will continue to send JSON by default.
      format.json do
        if !valid
          errors = comment.errors.map(&:message)
          return render json: { errors: errors }, status: :unprocessable_entity
        end

        if params[:context] == "project_sidebar"
          render_update_content_json({
            state_button_wrapper: render_to_string(
              partial: "pull_requests/state_button_wrapper",
              object: @pull,
              formats: :html,
              locals: {
                pull: @pull,
                addl_btn_classes: ["width-full mt-2"],
              },
            )
          })
        else
          # we reload the pull request here to get the updated list of commits since it can change if we reopen a closed PR
          pull_node = PullRequest::ShowLoader.issue_node(
            @pull.reload,
            current_repository,
            current_user,
            cap_filter: cap_filter,
            pagination_params: { per_page: params[:timeline_per_page], timeline_since: helpers.discussion_last_modified_at&.iso8601 }
          )
          partials = {
            timeline: render_to_string(
              partial: "pull_requests/timeline",
              object: @pull,
              formats: :html,
              locals: { pull_node: pull_node }
            )
          }
          if params[:comment_and_close].present? || params[:comment_and_open].present?
            partials.merge!({
              merging: render_to_string(
                partial: "pull_requests/merging",
                object: @pull,
                formats: :html,
              ),
              form_actions: render_to_string(
                partial: "pull_requests/form_actions",
                object: @pull,
                formats: :html,
                locals: {
                  pull: @pull,
                  issue_node: pull_node,
                },
              ),
              title: render_to_string(
                partial: "pull_requests/title",
                object: @pull,
                formats: :html,
                locals: {
                  sticky: params[:sticky] == "true",
                },
              ),
              pull_request_tab_count: render_to_string(
                partial: "navigation/repository/tab_counter",
                formats: :html,
                locals: {
                  count: current_repository.open_pull_request_count_for(current_user), # domain-isolation-query-violation:ignore:packages/issues (SELECT)
                  label: "Pull requests"
                }
              )
            })
          end
          render_update_content_json(partials)
        end
      end
      format.html do
        if valid
          anchor = comment ? "#issuecomment-#{comment.id}" : ""
          redirect_to pull_request_path(@pull) + anchor
        else
          flash[:error] = comment.errors.full_messages.to_sentence
          redirect_to :back
        end
      end
    end
  rescue ActiveRecord::RecordInvalid => e
    respond_to do |format|
      format.html do
        flash[:error] = e.record.errors.full_messages.to_sentence
        return redirect_to :back
      end
      format.json do
        errors = e.record.errors.map { |error| error.message }
        return render json: { errors: errors.to_sentence }, status: :unprocessable_entity
      end
    end
  end

  def dismiss_protip # rubocop:todo GitHub/UseRestfulActions
    T.must(current_user).dismiss_notice("continuous_integration_tip")

    head :ok
  end

  def set_collab # rubocop:todo GitHub/UseRestfulActions
    pull = current_repository.issues.find_by_number(params[:id].to_i).try(:pull_request)

    return render_404 if !pull || !pull.head_repository.repository.pushable_by?(current_user)

    if !!params[:collab_privs]
      pull.fork_collab_allowed!
    else
      pull.fork_collab_denied!
    end

    redirect_to pull_request_path(pull)
  end

  def resolve_conflicts # rubocop:todo GitHub/UseRestfulActions
    redirect_or_error = ensure_valid_pull_request
    return redirect_or_error if performed?

    unless logged_in? && @pull.head_repository && @pull.head_repository.pushable_by?(current_user, ref: @pull.head_ref_name)
      return render_404
    end

    can_push_merge_to_head = !@pull.head_branch_rule_evaluator&.required_linear_history_enabled?

    unless @pull.conflict_resolvable? && conflict_editor_enabled?(@pull) && can_push_merge_to_head
      return redirect_to pull_request_path(@pull)
    end

    render "pull_requests/resolve_conflicts", locals: { pull: @pull }
  end

  def ready_for_review # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless ensure_valid_pull_request

    return render_404 unless @pull.can_mark_ready_for_review?(current_user)

    begin
      @pull.ready_for_review!(user: current_user)
      flash[:notice] = "Marked pull request as ready for review."
    # ActiveRecord::RecordInvalid is the most expected exception type from `#ready_for_review!`
    # In case an exception with diff. type took place, user will see the Unicorn 500 error page
    # In that case, we will add the other exception type
    rescue ActiveRecord::RecordInvalid => e
      Failbot.report(e, "gh.pull_request.id": @pull.id)
      flash[:error] = "Something went wrong!"
    end

    redirect_to :back
  end

  def convert_to_draft # rubocop:todo GitHub/UseRestfulActions
    ensure_valid_pull_request
    return if performed?

    return render_404 unless @pull.can_convert_to_draft?(current_user)

    @pull.convert_to_draft(user: current_user)

    if T.must(request).xhr?
      head :ok
    else
      flash[:notice] = "Pull request review paused."
      redirect_back fallback_location: pull_request_path(@pull), allow_other_host: false
    end
  end

  class BadSuggestionError < StandardError; end

  def apply_suggestions # rubocop:todo GitHub/UseRestfulActions
    @pull = find_pull_request
    return render_404 unless @pull

    json = GitHub::JSON.parse(params[:changes])
    changes = Array(json).map do |change|
      raise BadSuggestionError unless change.respond_to?(:fetch)
      {
        commentId: change.fetch("commentId", ""),
        path: change.fetch("path", ""),
        suggestion: change.fetch("suggestion", []),
      }
    end

    inputs = {
      pull_request: @pull,
      changes: changes,
      message: params[:message].to_s,
      current_oid: params[:current_oid],
      sign: true
    }

    # Doing one query to find all review comments that will be used later on by `PullRequestReviewComment::ApplySuggestedChange#call`
    review_comments = begin
      PullRequestReviewComment.find(changes.map { |c| c[:commentId] })
    rescue ActiveRecord::RecordNotFound => e
      return render json: { error: "One or more of the suggestion comments has been deleted." }, status: :not_found
    end

    review_comments_hash = Hash[review_comments.map { |c| [c.id, c] }]

    changes = changes.map do |change|
      {
        path: change[:path],
        suggestion: change[:suggestion],
        comment: review_comments_hash[change[:commentId].to_i]
      }
    end

    inputs.merge!(
      changes: changes,
      viewer: current_user,
      remote_ip: T.must(request).remote_ip,
      user_agent: T.must(request).user_agent
    )

    begin
      PullRequestReviewComment::ApplySuggestedChange.call(inputs)
    rescue PullRequestReviewComment::ApplySuggestedChange::NotFoundError => e
      return render json: { error: e.message }, status: :not_found
    rescue PullRequestReviewComment::ApplySuggestedChange::ForbiddenError => e
      return render json: { error: e.message }, status: :forbidden
    rescue PullRequestReviewComment::ApplySuggestedChange::UnprocessableError => e
      return render json: { error: e.message }, status: :unprocessable_entity
    end

    flash[:notice] = "#{"Suggestion".pluralize(inputs[:changes].count)} successfully applied."
    head :ok
  rescue GitHub::JSON::ParseError, BadSuggestionError
    render json: { error: "Sorry, the changes couldn't be applied." }, status: :unprocessable_entity
  end

  def run_action_required_workflows # rubocop:todo GitHub/UseRestfulActions
    @pull = find_pull_request
    return render_404 unless @pull
    return render_404 unless current_repository.writable_by?(current_user)

    workflow_run_ids = []
    @pull.action_required_check_suites(head_sha: @pull.head_sha).each do |check_suite|
      begin
        check_suite.rerequest(actor: current_user)
        workflow_run_ids << check_suite.workflow_run.id
      rescue CheckSuite::ActionsDependency::ExpiredWorkflowRunError, CheckSuite::AlreadyRerunningError, CheckSuite::DisabledWorkflowError, CheckSuite::NotRerequestableError => e
        flash[:error] = "Unable to re-run one or more workflows. Check if the workflows are already running, are more than 30 days old, or are disabled."
        GitHub.dogstats.increment("workflow.action_required_rerquest_failed", tags: ["error:#{e.class.name&.demodulize}"])
      end
    end

    GlobalInstrumenter.instrument("workflow.action_required_approved", {
      pull_request_id: @pull.id,
      actor_id: T.must(current_user).id,
      repo_id: current_repository.id,
      workflow_run_ids: workflow_run_ids.sort!,
    })

    redirect_to pull_request_path(@pull)
  end

  # deferred_commits_data takes two optional parameters:
  #    results_to_fetch - integer indicating how big of a window to grab
  #    start_entry - integer indicating where to begin within the pull commits list for grabbing async data
  def deferred_commits_data # rubocop:todo GitHub/UseRestfulActions
    @pull = find_pull_request
    return render_404 unless @pull
    return render_404 if @pull.hide_from_user?(current_user)

    commits = @pull.changed_commits
    commit_count = commits.length
    start_index = params[:start_entry].to_i
    results_to_fetch = params[:results_to_fetch].nil? ? COMMITS_TO_FETCH_DATA_FOR_AT_A_TIME : params[:results_to_fetch].to_i
    commits = commits.slice(start_index, results_to_fetch)
    next_starting_index = start_index + results_to_fetch > commit_count ? commit_count : start_index + results_to_fetch
    load_more = next_starting_index != commit_count

    respond_to do |format|
      format.json do
        render json: { deferredCommits: build_deferred_commit_payload(commits, current_repository, current_user),
          nextIndex: next_starting_index,
          loadMore: load_more,
          #loading is set to false because that is how we tell the front end that we have gotten the first set
          #of results back
          loading: false  }
      end
    end
  end

  protected

  def use_actions_ux?
    false
  end
  helper_method :use_actions_ux?

  def valid_tab?
    params[:tab].blank? || %w{discussion commits files tasks checks}.include?(params[:tab])
  end

  def reject_bully?(pull = nil)
    return false if current_user_can_push?
    if blocked_by_owner? || (pull && blocked_by_author?(pull.user))
      flash[:error] = "You can't perform that action at this time."
      redirect_to current_repository.permalink
      true
    end
  end

  private

  def patch_action_request_is_rate_limited?
    !logged_in?
  end

  def patch_action_rate_limit_key
    key_base = "#{self.class.to_s.underscore}:#{action_name}"
    actor_identifier = request.env.fetch("HTTP_X_SSL_JA3_HASH", nil)
    actor_identifier = request.remote_ip if actor_identifier.blank?
    "#{key_base}:#{actor_identifier}"
  end

  def change_branch_async
    new_base = Base64.decode64(params[:new_base_binary])

    result = PullRequests::ChangeBase.execute(pull_request: @pull, user: T.must(current_user), new_base:)

    case result
    when PullRequests::ChangeBase::Success
      render json: { orchestration: { url: pull_request_orchestration_status_url(orchestration_id: result.orchestration.id) } }
    when PullRequests::ChangeBase::Error
      render json: { error_message: result.error_message }, status: :unprocessable_entity
    else
      T.absurd(result)
    end
  end

  def set_page_responsive
    @page_responsive = true
  end

  def record_stats
    if action_name == "files"
      stats.add_tags "defer_syntax_highlighted_diffs:true"
    end

    stats.instrument_controller_action do
      yield
      response.successful?
    end
  end

  def show_blankslate?(check_suites, selected_check_run, current_repository)
    return false if check_suites.any?
    return false if selected_check_run
    return false if current_repository.has_apps_that_write_checks?
    true
  end

  def workflows_loading?(check_suites, selected_check_run)
    # selected_check_run will be nil if no check runs have been created (yet)
    return false if selected_check_run

    check_suites.any? { |check_suite| check_suite.actions_app? && !check_suite.completed? }
  end

  def find_pull_request
    PullRequest.with_number_and_repo(params[:id].to_i, current_repository, include: [{ issue: :comments }])
  end

  # Private: For a given ref name, redirect to the appropriate pull request
  # path if one exists, or 404 otherwise.
  #
  # Returns the redirect or render_404 result.
  def redirect_or_404(ref)
    # redirect to number version if ref is a branch name,
    # redirect to new if ref is a branch with no pull request
    # 404 otherwise
    if pull = current_repository.pull_requests.for_branch(ref).last
      redirect_to pull_request_path(pull)
    elsif ref =~ /[:.]/ || current_repository.heads.include?(ref)
      redirect_to new_pull_request_path(range: ref)
    else
      render_404
    end
  rescue ActionController::UrlGenerationError
    render_404
  end

  # Private: Validate the requested pull request ID. If necessary redirect to
  # a more appropriate URL or return a 404 if the PR isn't/shouldn't be
  # available.
  def ensure_valid_pull_request
    GitHub.dogstats.time("pull_request.ensure_valid_pull_request", tags: dogstats_request_tags) do
      if params[:id] =~ /\D/
        return redirect_or_404(params[:id])
      end

      @pull = find_pull_request

      return redirect_to(issue_path(id: params[:id])) unless @pull
      return redirect_to(pull_request_path @pull) unless valid_tab?

      return render_404 if @pull.hide_from_user?(current_user)

      @prose_url_hints = { tab: "files" }

      @pull.set_diff_options(
        use_summary: true,
        ignore_whitespace: ignore_whitespace?(@pull, params, current_user, logged_in?),
      )
    end
  end

  def conflict_editor_enabled?(pull)
    return true unless pull.cross_repo?

    GitHub.cross_repo_conflict_editor_enabled?
  end

  # Validates the provided parameter is a valid sha, or nil
  def valid_sha_param?(param_name)
    param = params[param_name]
    param.nil? || GitRPC::Util.valid_full_oid?(param)
  end

  def load_diff
    @pull_comparison.ignore_whitespace = ignore_whitespace?(@pull_comparison.pull, params, current_user, logged_in?)
    @pull_comparison.diff_options[:use_summary] = true
    @pull_comparison.diff_options[:top_only] = true

    GitHub.dogstats.time("diff.load.initial", tags: dogstats_request_tags) do
      @pull_comparison.diffs.apply_auto_load_single_entry_limits!
      @pull_comparison.diffs.load_diff(timeout: request_time_left / 2)
    end
  end

  # Prepare for rendering the files tab
  #
  # pull_comparison - PullRequest::Comparison specifying whether the PR's diff will be rendered.
  #
  # Returns nothing.
  def prepare_for_rendering_files(pull_comparison:)
    return unless pull_comparison

    CodeScanning::ReviewCommentComponent.preload_review_comments(pull_request: @pull)

    review_threads = pull_comparison.review_threads_for(viewer: current_user)

    review_threads = review_threads.map(&:activerecord_pull_request_review_thread)

    file_threads = pull_comparison.file_review_threads_for(viewer: current_user).map(&:activerecord_pull_request_review_thread)
    review_threads.concat(file_threads)

    GitHub::PrefillAssociations.prefill_associations(review_threads, :pull_request_review)
    review_threads.each { |thread| thread.current_comparison = pull_comparison }

    PullRequests::ReviewThreadComponent.preload_review_threads(review_threads: review_threads, viewer: current_user, pull_request: @pull)

    review_comments = review_threads.flat_map do |thread|
      page_info = thread.prelude_paginated_review_comments_for(current_user, PullRequests::ReviewThreadBodyComponent.pagination_params)
      page_info[:first_group] + (page_info[:last_group] || [])
    end
    GitHub::PrefillAssociations.prefill_associations(review_comments, :repository, available_records: [current_repository])

    PullRequests::ReviewCommentComponent.preload_review_comments(
      review_comments: review_comments,
      reviews: review_threads.map(&:pull_request_review),
      pull_request: @pull,
      viewer: current_user,
      cap_filter: cap_filter
    )
  end

  def can_skip_creating_comment?
    params[:comment_and_close].present? ||
      params[:comment_and_open].present?
  end

  # If it's empty, you can't issue a pull request.  There will be no
  # base SHA to merge against.
  def check_for_empty_repository
    if current_repository.empty?
      redirect_to current_repository
    end
  end

  def ensure_pull_head_pushable
    @pull = current_repository.issues.find_by_number(params[:id].to_i).try(:pull_request) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    return render_404 if @pull.nil?
    return writable_repository_required unless @pull.head_repository.writable?
    render_404 unless @pull.head_repository.pushable_by?(current_user)
  end

  # Reload the pull so the deletable/restorable status is current,
  # then render updates for the event list and the merge/delete buttons.
  def render_head_ref_update(status:, unretryable: false)
    @pull.reload
    merging_error = nil
    if status == :unprocessable_entity
      merging_error = { form_target: "js-cleanup-branch-form", unretryable: unretryable }
    end
    respond_to do |format|
      # The `format.json` block must stay at the top here if any format
      # block is added in future, so that when the `Accept` header is `*/*`
      # we will continue to send JSON by default.
      format.json do
        pull_node = PullRequest::ShowLoader.issue_node(@pull, current_repository, current_user, cap_filter: cap_filter, pagination_params: { per_page: params[:timeline_per_page], timeline_since: helpers.discussion_last_modified_at&.iso8601 })
        render_update_content_json({
          timeline: render_to_string(
                partial: "pull_requests/timeline",
                object: @pull,
                formats: :html,
                locals: {
                  pull_node: pull_node,
                },
              ),
              merging: render_to_string(
                partial: "pull_requests/merging",
                object: @pull,
                formats: :html,
                locals: {
                  merging_error: merging_error,
                },
              ),
              form_actions: render_to_string(
                partial: "pull_requests/form_actions",
                object: @pull,
                formats: :html,
                locals: {
                  pull: @pull,
                  issue_node: pull_node,
                },
              ),
        }, status: status)
      end
    end
  end

  # Internal: Provide a better failure message than simply taking the validation errors
  #
  # e - the ActiveRecord::RecordInvalid exception from the creation failure
  #
  # Returns a String
  def human_failure_message(e)
    pr = e.record

    # e.record can be an Issue, raised in PullRequest.create_for.
    return e.message unless pr.is_a?(PullRequest)

    if bad_branches = pr.missing_refs
      if bad_branches.length == 1
        "The #{bad_branches.first} branch doesn’t exist."
      else
        "The #{bad_branches.join(' and ')} branches don’t exist."
      end
    elsif [:base_ref, :head_ref].any? { |attr| pr.errors[attr].include?(GitHub::Validations::Unicode3Validator::ERROR_MESSAGE) }
      "Branch names cannot contain unicode characters above 0xffff."
    else
      e.message
    end
  end

  def pull_request_authorization_token
    T.must(current_user).signed_auth_token expires: 60.seconds.from_now,
                                   scope: pull_request_authorization_token_scope_key
  end

  def build_pull_request_diff_url
    route_options ||= {}

    if GitHub.prs_content_domain?
      route_options[:host] = GitHub.prs_content_host_name
    end

    if current_repository.private?
      route_options[:token] = pull_request_authorization_token
    end

    route_options[:full_index] = params[:full_index]

    pull_request_raw_diff_url(route_options)
  end

  def build_pull_request_patch_url
    route_options ||= {}

    if GitHub.prs_content_domain?
      route_options[:host] = GitHub.prs_content_host_name
    end

    if current_repository.private?
      route_options[:token] = pull_request_authorization_token
    end

    route_options[:full_index] = params[:full_index]

    pull_request_raw_patch_url(route_options)
  end

  def request_reflog_data(via)
    super(via).merge({ pr_author_login: @pull.safe_user.display_login })
  end

  def content_authorization_required
    authorize_content(:pull_request, repo: current_repository)
  end

  def invalid_author_email?(author_email)
    author_email && (!GitHub.choose_commit_email_enabled? || !current_user&.author_emails.include?(author_email))
  end

  class BadRange < StandardError; end

  def route_supports_advisory_workspaces?
    return false if action_name == "merge"
    return true unless action_name == "show"

    %w(discussion status commits files).include?(specified_tab)
  end

  def no_cache
    return unless T.must(request).get?
    expires_now
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

  def async_mark_comparison_as_seen(comparison, user:)
    message = {
      pull_request_id: comparison.pull.id,
      user_id: user.id,
      start_oid: comparison.start_commit.oid,
      end_oid: comparison.end_commit.oid,
    }

    GitHub.hydro_publisher.publish(
      message,
      schema: "github.pull_requests.v1.MarkPullRequestComparisonAsSeen",
      topic_format_options: { format_version: Hydro::Topic::FormatVersion::V2 },
    )
  end

  def mark_pull_notification_as_read(thread)
    async_mark_thread_as_read thread
  end

  memoize def default_merge_method
    Platform::Models::PullRequestMergeRequirements.new(@pull, nil, nil, nil, current_user).merge_method.sync.upcase
  end

  def render_pull_requests_react(pull, range)
    add_client_feature_flag(
      [
        :accessible_code_button,
        :copilot_workspace,
        :prx_commits_feedback_badge,
        :diff_inline_comments,
        :prx_files,
        :prx_files_lite_throttle,
        :prx_files_medium_throttle,
        :prx_dynamic_split_pref,
        :react_diff_line_type_character_correction,
      ]
    )

    # This is overly repetive, however it is temporary. As we are building out
    # the PR Files Tab in react, we are also moving the PR Commits tab to a new
    # data router. Neither of these are fully fleshed out, so we currently need
    # a small package to allow us to split off the files tab. In time, we will
    # be able to move entirely back into the `pull-requests` package and then we
    # can remove this whole block.
    if action_name == "files"
      begin
        payload = build_prx_files_payload(pull, range)

        return render_react_app(
          app_name: "pull-request-files",
          app_payload_generator: -> {
            {
              helpUrl: GitHub.help_url,
              refListCacheKey: ref_list_cache_key,
            }
          },
          custom_tags: [
            "referrer_controller_action:pull_requests##{action_name}",
            "is_react:true",
            "is_data_router:false"
          ],
          page_data: react_page_metadata(pull, action_name),
          layout: "layouts/repository_with_container",
          payload: payload,
          title: pull_request_page_title(pull),
          data_router_enabled: false,
        )
      rescue TypeError # raised when unable to init pull request comparison
        return render "pull_requests/files_unavailable"
      rescue FilesUnavailable, GitRPC::ObjectMissing
        return render "pull_requests/files_unavailable"
      rescue NonCanonicalRange => e
        return redirect_to(range: e.canonical_range)
      rescue OrphanCommit => e
        return render "pull_requests/orphan_commit", status: :not_found, locals: { oid2: e.oid2 }
      rescue GitHub::Diff::Parser::UnrecognizedText
        return render "pull_requests/unrecognized_diff_text", status: :not_found, locals: { pull: pull }
      end
    end

    current_path = defined?(path_string_for_display) ? path_string_for_display : ""
    commits_data = PullRequests::PageData::CommitsPayload.build(
      current_path:,
      current_user:,
      pull_request: pull,
      tree_name: tree_name_for_display
    )

    payload = PullRequestsCommitsPayload.new(commits_data)

    respond_to do |format|
      format.html do
        header_data = PullRequests::PageData::HeaderPayload.build(
          current_user:,
          pull_request: pull,
        )

        render_react_html(
          title: pull_request_page_title(pull),
          payload: payload,
          nested_payloads: [PullRequestsLayoutPayload.new(header_data)],
          app_name: "pull-requests",
          app_payload_generator: -> {
            {
              helpUrl: GitHub.help_url,
              refListCacheKey: ref_list_cache_key,
            }
          },
          custom_tags: [
            "referrer_controller_action:pull_requests##{action_name}",
            "is_react:true"
          ],
          page_data: react_page_metadata(pull, action_name),
          layout: "layouts/repository_with_container",
        )
      end

      format.json do
        render_react_json(title: pull_request_page_title(pull), payload: payload)
      end
    end

  # BadRange error is handled the same for PR#files and PR#commits
  rescue BadRange
    disable_account_switcher_popover
    render "pull_requests/bad_range", status: :not_found
  end

  def build_prx_files_payload(pull_request, range)
    pull_comparison = calculate_comparison(pull_request, range, current_user)

    limit_config = PullRequests::PageData::Files::PageLimitConfig.new(
      repository: current_repository,
      user: current_user,
    )

    files_data = PullRequests::PageData::Files::Loader.load(
      comparison: T.must(pull_comparison),
      current_user: current_user,
      file_filter: {
        selected_file_extensions: params[FILE_TYPE_FILTER_PARAM],
        show_deleted_files: !deleted_files_hidden?,
        show_only_manifest_files: manifest_files_active?,
        show_only_owned_files: only_owned_by_active?,
        show_vendored_files: !vendored_files_hidden?,
        show_viewed_files: !viewed_files_hidden?,
      },
      ignore_whitespace: ignore_whitespace?(pull_request, params, current_user, logged_in?),
      include_codeowners: only_owned_by_active?,
      timeout: request_time_left / 2,
      highlighting_strategy: PullRequests::PageData::Diffs::Contents::Loader.syntax_highlighting_method(request.user_agent, current_user),
      pull_request: pull_request,
      cap_filter: cap_filter,
      user_session: user_session,
      limit_config: limit_config,
    )

    PullRequests::PageData::Files::Payload.call(files_data).as_json
  end

  def react_page_metadata(pull, action_name)
    {
      selected_link: :repo_pulls,
      send_vitals: true,
      container_xl: true,
      stafftools:    UrlHelpers.stafftools_repository_pull_request_path(
                       pull.repository.owner_display_login, pull.repository.name, pull.number),
      richweb: {
        title:       pull_request_page_title(pull),
        url:         pull.url.to_s,
        description: pull.repository.feature_enabled?(:new_pr_page_description) ? page_description(pull) : pull.body_text,
        image:       pull.repository.show_enhanced_og_image? ? pull.og_image_url : pull.repository.open_graph_image_url(T.unsafe(self).current_user),
        author:      pull.user&.display_login,
      },
      dashboard_pinnable_item_id: pull.id,
      html_class: "js-skip-scroll-target-into-view", # opt out of behavior.js scroll management
      class: action_name == "files" ? "full-width" : "", # force full width for files changed
    }
  end

  class BadRange < StandardError; end
  class FilesUnavailable < StandardError; end

  class NonCanonicalRange < StandardError
    attr_accessor :canonical_range

    def initialize(canonical_range)
      @canonical_range = canonical_range
    end
  end

  class OrphanCommit < StandardError
    attr_accessor :oid2

    def initialize(oid2)
      @oid2 = oid2
    end
  end

  def page_description(pull_request)
    viewer = T.unsafe(self).current_user
    cap_filter = T.unsafe(self).cap_filter

    truncate(pull_request.body_text(context: pull_request.body_html_context(viewer:, cap_filter:)) || "", length: 200)
  end

  def use_repository_cluster_replicas(&block)
    use_replica_clusters([ApplicationRecord::Repositories], &block)
  end

  class PullRequestsLayoutPayload < ReactPayload::Base
    def route_id
      "pullRequestsLayoutRoute"
    end

    sig { params(header_data: T::Hash[String, T.untyped]).void }
    def initialize(header_data)
      @header_data = header_data
    end

    def payload
      @header_data
    end
  end

  class PullRequestsCommitsPayload < ReactPayload::Base
    def route_id
      "pullRequestsCommitsRoute"
    end

    sig { params(commits_data: T::Hash[String, T.untyped]).void }
    def initialize(commits_data)
      @commits_data = commits_data
    end

    def payload
      @commits_data
    end
  end
end
