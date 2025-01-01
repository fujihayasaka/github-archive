# typed: true
# frozen_string_literal: true

require "github-launch"

class ChecksController < AbstractRepositoryController
  include ControllerMethods::CheckAnnotations

  before_action :require_push_access, except: [:index, :show, :annotations, :checks_state_summary, :check_logs, :step_logs, :live_logs]

  stylesheet_bundle :actions

  before_action :all_color_mode_themes

  around_action :record_index_metrics, only: [:index]
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Spokes,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Configurations,
    only: [:annotations]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Spokes,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    only: [:check_logs]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Spokes,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Configurations,
    only: [:checks_state_summary]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Spokes,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql2,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Permissions,
    ApplicationRecord::Iam,
    ApplicationRecord::Memex,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Spokes,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    only: [:live_logs]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Spokes,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Spokes,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    only: [:step_logs]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:annotations, :check_logs, :checks_state_summary, :index, :step_logs], optional: true

  private def record_index_metrics
    action_start_time = GitHub::Dogstats.monotonic_time

    yield

    GitHub.dogstats.timing_since("checks.index", action_start_time, tags: [
      "logged_in:#{!!logged_in?}",
      "dreamlifter_enabled:#{GitHub.actions_enabled?}",
    ])
  end

  def index
    begin
      commit = Repositories.domain.commits.by_oid(repository: current_repository, commit_oid: params[:ref])
      if commit.nil?
        render_404 and return
      end
    rescue GitRPC::ObjectMissing, RepositoryObjectsCollection::InvalidObjectId
      render_404 and return
    end

    @check_suites = current_repository.check_suites.where(head_sha: T.must(commit).oid).most_recent

    check_suite = T.let(nil, T.nilable(CheckSuite))
    if params[:check_suite_id] &&
      # Use .detect here not .find so as not to trigger a DB call.
      check_suite = @check_suites.detect { |cs| cs.id == params[:check_suite_id].to_i }
    end

    check_run = T.let(nil, T.nilable(CheckRun))
    [check_suite].concat(@check_suites.to_a).compact.each do |check_suite|
      check_run = Checks.domain.check_runs.latest_for_check_suite(check_suite, first_only: true).first
      break if check_run
    end
    @default_check_run = check_run

    if @default_check_run
      annotation_details = load_annotation_details(check_run: @default_check_run)
    end

    commit_check_runs = CheckRun.for_sha_and_repository_id_with_limit(current_repository.id, T.must(commit).oid, CheckRun.default_max_check_suites_per_sha_limit)

    render "checks/show", locals: {
      commit: commit,
      selected_check_run: @default_check_run,
      check_suites: @check_suites,
      blankslate: show_blankslate?(@check_suites, @default_check_run, current_repository),
      workflows_loading: workflows_loading?(@check_suites, @default_check_run),
      annotation_details: annotation_details,
      commit_check_runs: commit_check_runs,
      show_check_run_logs: true
    }, layout: "repository"
  end

  def live_logs # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless logged_in?

    check_run = current_check_run
    return render_404 unless check_run.present?

    streaming_log_url = check_run.streaming_log_url
    return render_404 unless streaming_log_url.present?

    result = check_run.request_streaming_log_url_from_actions_service

    if !result.call_succeeded?
      GitHub.dogstats.increment("actions.exchange_url_request.succeeded", tags: ["live_logs"])
      error_message = result.options[:message] || "RPC call failed due to unknown error."
      render json: { success: false, errors: [error_message], data: {} }, status: 500
    else
      GitHub.dogstats.increment("actions.exchange_url_request.failed", tags: ["live_logs"])
      render json: { success: true, errors: [], data: { authenticated_url: result.value.authenticated_url } }, status: :ok
    end
  end

  def step_logs # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless logged_in?

    check_run = current_check_run

    if check_run&.expired_logs?
      return render status: 410, plain: "Logs not available. Check retention settings."
    end

    return render_404 unless check_run.present?

    check_step =
      if check_run.passthrough_steps?
        check_run.steps_from_backend.find { |step| step.number == params[:step].to_i }
      else
        check_run.get_steps.find { |step| step.number == params[:step].to_i }
      end

    check_step_log_url = check_step&.get_signed_completed_log_url

    if check_step_log_url.blank?
      GitHub.dogstats.increment("actions.exchange_url_request.failed", tags: ["step_logs"])
      return render_404
    end

    GitHub.dogstats.increment("actions.exchange_url_request.succeeded", tags: ["step_logs"])
    redirect_to check_step_log_url, status: 307
  end

  def check_logs # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless logged_in?

    check_run = current_check_run
    return render_404 unless check_run.present?

    # four-nines only
    # unless the job is completed, display the system logs from results
    if check_run.system_logs_from_results?
      return render plain: check_run.system_logs || ""
    end

    return render_404 unless check_run.completed_log_url.present?

    check_run_log_url = check_run.get_signed_completed_log_url

    if check_run_log_url.blank?
      flash[:error] = "Failed to generate URL to download logs."
      redirect_back fallback_location: check_run_path(id: check_run.id)
    else
      redirect_to check_run_log_url, status: 307
    end
  end

  def show
    return redirect_to checks_path(ref: params[:ref]) unless request.xhr?

    begin
      commit = current_repository.commits.find(params[:ref])
    rescue GitRPC::ObjectMissing
      render_404 and return
    end

    commit_check_runs = CheckRun.for_sha_and_repository_id(commit.oid, current_repository.id)
    check_run = commit_check_runs.find_by(id: params[:id])
    return render_404 if check_run.nil?

    pull = current_repository.pull_requests.find_by_id(params[:pull])

    respond_to do |format|
      format.html do
        annotation_details = load_annotation_details(check_run: check_run)
        render partial: "checks/checks_summary", locals: {
          check_suite: check_run.check_suite,
          check_run: check_run,
          commit: commit,
          pull: pull,
          annotation_details: annotation_details,
          commit_check_runs: commit_check_runs,
          show_check_run_logs: true
        }
      end
    end
  end

  def annotations # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless request.xhr?

    begin
      commit = current_repository.commits.find(params[:ref])
    rescue GitRPC::ObjectMissing
      render_404 and return
    end

    check_run = CheckRun.for_sha_and_repository_id(commit.oid, current_repository.id).find_by(id: params[:id])
    return render_404 if check_run.nil?

    pull = current_repository.pull_requests.find_by_id(params[:pull])

    annotation_details = load_annotation_details(check_run: check_run, after: params[:after])

    respond_to do |format|
      format.html do
        render partial: "checks/checks_annotations", locals: {
          pull: pull,
          check_run: check_run,
          annotation_details: annotation_details,
          commit: commit,
        }
      end
    end
  end

  def checks_state_summary # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless request.xhr?

    begin
      commit = current_repository.commits.find(params[:ref])
    rescue GitRPC::ObjectMissing
      render_404 and return
    end

    check_suites = current_repository.check_suites.where(head_sha: commit.oid).most_recent

    respond_to do |format|
      format.html do
        render partial: "checks/checks_state_summary", locals: {
          check_suites: check_suites,
          head_sha: commit.oid,
        }
      end
    end
  end

  private

  def current_check_run
    commit = current_repository.commits.find(params[:ref])
    @check_run ||= CheckRun.for_sha_and_repository_id(commit.oid, current_repository.id).find_by(id: params[:id])
  end

  def show_blankslate?(check_suites, default_check_run, current_repository)
    return false if check_suites.any?
    return false if !default_check_run.nil?
    return false if current_repository.has_apps_that_write_checks?
    true
  end

  def workflows_loading?(check_suites, default_check_run)
    # default_check_run will be nil if no check runs have been created (yet)
    return false if default_check_run

    check_suites.any?(&:actions_app?)
  end

  def require_push_access
    render_404 unless current_user_can_push?
  end

  def use_actions_ux?
    false
  end
  helper_method :use_actions_ux?

  def route_supports_advisory_workspaces?
    parent_repository_can_have_actions_on_private_forks? || super
  end
end
