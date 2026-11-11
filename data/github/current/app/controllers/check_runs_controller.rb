# typed: true
# frozen_string_literal: true

class CheckRunsController < AbstractRepositoryController
  include ControllerMethods::CheckAnnotations

  before_action :require_push_access, except: [:show, :show_checks_wait_partial, :show_header_partial, :show_toolbar_partial]

  helper_method :use_actions_ux?

  stylesheet_bundle :actions

  before_action :all_color_mode_themes

  around_action :record_show_metrics, only: [:show]
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Spokes,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    ApplicationRecord::ActionsEnvironments,
    only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    only: [:show_header_partial]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Spokes,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    only: [:show_toolbar_partial]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show], optional: true

  private def record_show_metrics
    action_start_time = GitHub::Dogstats.monotonic_time

    yield

    GitHub.dogstats.timing_since("check_runs.show", action_start_time, tags: [
      "logged_in:#{!!logged_in?}",
      "dreamlifter_enabled:#{GitHub.actions_enabled?}",
    ])
  end

  def show
    return render_404 if request.xhr?

    check_run = Checks.domain.check_runs.for_id(params[:id].to_i, repository_id: current_repository.id) if params[:id]
    if check_run.nil? || T.must(check_run.check_suite).repository_id != current_repository.id
      render_404 and return
    end

    check_run = (T.must(check_run))

    head_sha = T.must(check_run.check_suite).head_sha
    unless current_repository.commits.exist?(head_sha)
      render_404 and return
    end

    check_suite_focus = params[:check_suite_focus] == "true"
    if check_suite_focus && check_run.workflow_job_run.present?
      redirect_to actions_job_path(workflow_run_id: T.must(check_run.workflow_job_run).workflow_run_id, job_id: check_run.id, pr: params[:pr]) and return
    end

    # contains the most recent 25 check suites
    check_suites = check_suite_focus ? [check_run.check_suite] : current_repository.check_suites.where(head_sha: head_sha).most_recent
    commit       = Repositories.domain.commits.by_oid(repository: current_repository, commit_oid: head_sha)
    if commit.nil?
      render_404 and return
    end

    if use_actions_ux?(check_run)
      # This is only required when a non-actions check is rendered with the Actions frame
      annotation_details = load_annotation_details(check_run: check_run) unless check_run.is_actions_check_run?

      execution = find_execution(check_run.workflow_job_run)

      render "actions/workflow_runs/show",
        layout: "repository",
        locals: {
          commit: commit,
          selected_check_run: check_run,
          blankslate: false,
          annotation_details: annotation_details,
          show_check_run_logs: true,
          execution: execution,
          retry_blankstate: false
        }
    else
      annotation_details = load_annotation_details(check_run: check_run)

      commit_check_runs = if check_suite_focus
        Checks.domain.check_runs.unsafe_latest_for_check_suite(T.must(check_run.check_suite))
      else
        CheckRun.for_sha_and_repository_id_with_limit(current_repository.id, T.must(commit).oid, CheckRun.default_max_check_suites_per_sha_limit)
      end

      prev_url = request.headers["HTTP_REFERER"] # need to determine what tab we just came from to determine which tab should be highlighted next

      render "checks/show", locals: {
        commit: commit,
        selected_check_run: check_run,
        check_suites: check_suites,
        blankslate: false,
        annotation_details: annotation_details,
        commit_check_runs: commit_check_runs,
        show_check_run_logs: true,
        highlight_tab: get_highlight_tab(check_suites, prev_url)
      }
    end
  end

  def show_checks_wait_partial # rubocop:todo GitHub/UseRestfulActions
    check_run = find_check_run
    return head :not_found unless check_run && request.xhr?

    render partial: "checks/checks_wait", locals: { check_run: check_run }
  end

  def show_header_partial # rubocop:todo GitHub/UseRestfulActions
    check_run = find_check_run
    return head :not_found unless check_run && request.xhr?

    render partial: "checks/checks_header", locals: { check_run: check_run }
  end

  def show_toolbar_partial # rubocop:todo GitHub/UseRestfulActions
    check_run = find_check_run
    return head :not_found unless check_run && request.xhr?

    head_sha = check_run.check_suite.head_sha
    commit = T.must(Repositories.domain.commits.by_oid(repository: current_repository, commit_oid: head_sha))
    commit_check_runs = CheckRun.for_sha_and_repository_id_with_limit(current_repository.id, commit.oid, CheckRun.default_max_check_suites_per_sha_limit)

    pull = current_repository.pull_requests.find_by(id: params[:pull_id]) if params[:pull_id]

    check_suites = current_repository.check_suites.where(head_sha: head_sha).most_recent

    render partial: "checks/checks_toolbar", formats: :html, locals: {
      view: create_view_model(Checks::ChecksToolbarView,
        commit_check_runs: commit_check_runs,
        commit: commit,
        check_suite: check_run.check_suite,
        check_suites: check_suites,
        selected_check_run: check_run,
        pull: pull,
      )
    }
  end

  def rerequest # rubocop:todo GitHub/UseRestfulActions
    check_run = find_check_run
    return render_404 unless check_run

    if check_run.check_suite.check_runs_rerunnable
      check_run.rerequest(actor: current_user)

      head :ok and return if request.xhr?

      flash[:notice] = "You have successfully requested #{check_run.visible_name} be rerun."
      redirect_to :back
    else
      head :bad_request and return if request.xhr?

      flash[:error] = "Re-runs for individual check runs are disabled for this check suite."
      redirect_to :back and return
    end

  end

  def request_action # rubocop:todo GitHub/UseRestfulActions
    check_run = find_check_run
    return render_404 unless check_run

    requested_action = { identifier: params[:identifier] }

    check_run.request_action(actor: current_user, requested_action: requested_action)
    flash[:notice] = "You have successfully requested '#{params[:label]}' on #{check_run.visible_name}."
    redirect_to :back
  end

  private

  def require_push_access
    render_404 unless current_user_can_push?
  end

  def find_check_run
    check_run = CheckRun.includes(:check_suite).where(id: params[:id]).first
    if !check_run || T.must(check_run.check_suite).repository_id != current_repository.id
      return nil
    end
    check_run
  end

  def use_actions_ux?(check_run = nil)
    (params[:ux_refresh] == "true" || params[:check_suite_focus] == "true") && (check_run.nil? || check_run.check_suite.actions_app?)
  end

  def highlight_actions_tab?(check_suites = nil)
    !check_suites.nil? && check_suites.any? { |check_suite| check_suite.actions_app? }
  end

  def highlight_pulls_tab?(prev_url = nil)
    prev_url.present? && prev_url.include?("pull")
  end

  def get_highlight_tab(check_suites = nil, prev_url = nil)
    # If any of the check suites are from actions, highlight the actions tab.
    # Otherwise, if the request came from the PR tab, highlight the PR tab.
    # If the request is neither actions nor PR, highlight the code tab.
    if highlight_actions_tab?(check_suites)
      return :repo_actions
    end

    highlight_pulls_tab?(prev_url) ? :repo_pulls : :repo_source
  end

  def find_execution(workflow_job_run)
    if workflow_job_run.present?
      workflow_job_run.workflow_run_execution
    end
  end

  def route_supports_advisory_workspaces?
    parent_repository_can_have_actions_on_private_forks? || super
  end
end
