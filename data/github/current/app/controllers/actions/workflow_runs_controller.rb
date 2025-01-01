# typed: false
# frozen_string_literal: true

class Actions::WorkflowRunsController < AbstractRepositoryController
  include ActionsControllerMethods
  include GateRequestHelper

  layout "repository"

  before_action :actions_or_dependabot_enabled_for_repo?
  before_action :should_show_selected_workflow_run?

  javascript_bundle :"workflow-run", :diffs
  stylesheet_bundle :actions

  before_action :all_color_mode_themes

  preload_features [:actions_green_trees], only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::IssuesPullRequests,
    only: [:delete_pull_requests_list]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::RepositoriesActionsChecks,
    only: [:action_required_partial]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Spokes,
    only: [:annotations_partial]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::ActionsEnvironments,
    only: [:approvals_banner_partial]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::ActionsEnvironments,
    only: [:approvals_partial]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::RepositoriesActionsChecks,
    only: [:artifacts_partial]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Iam,
    only: [:attempts, :new_attempts_menu]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::ActionsEnvironments,
    only: [:failed_jobs]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::ActionsEnvironments,
    only: [:graph_partial]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Spokes,
    only: [:header_partial]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::ActionsEnvironments,
    only: [:job_downstream_list]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Spokes,
    ApplicationRecord::ActionsEnvironments,
    only: [:job_steps]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Spokes,
    only: [:job_step_backscroll]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::ActionsEnvironments,
    only: [:job_summary_content]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::ActionsEnvironments,
    only: [:job_summary_partial]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::RepositoriesActionsChecks,
    only: [:job_summary_raw]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::RepositoriesActionsChecks,
    only: [:jobs_list]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Spokes,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Memex,
    ApplicationRecord::Billing,
    ApplicationRecord::Iam,
    ApplicationRecord::RepositoriesPushes,
    ApplicationRecord::ActionsEnvironments,
    only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Spokes,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Memex,
    ApplicationRecord::Billing,
    ApplicationRecord::Iam,
    only: [:workflow_file]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Iam,
    only: [:navigation_partial]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Spokes,
    ApplicationRecord::Mysql2,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Memex,
    ApplicationRecord::Billing,
    only: [:usage]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Spokes,
    only: [:workflow_run_summary_partial]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::RepositoriesActionsChecks,
    only: [:job_rerun_dialogs_partial]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::RepositoriesActionsChecks,
    only: [:concurrency_banner_partial]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:attempts, :new_attempts_menu, :show, :usage, :workflow_file],
    optional: true

  def show
    return render_404 if request.xhr?

    workflow_run = find_workflow_run_with_graph
    return render_404 unless workflow_run

    check_suite = workflow_run.check_suite
    attempt = params[:attempt]

    begin
      execution = attempt.present? ? find_execution_attempt_with_graph!(workflow_run, attempt) : find_execution_with_graph(workflow_run)
    rescue ActiveRecord::RecordNotFound
      return render_404
    end

    return render_404 unless !workflow_run.actor&.spammy? || workflow_run.actor == current_user || current_user&.site_admin?

    show_spammy_warning = workflow_run.actor&.spammy? && current_user&.site_admin?

    begin
      commit = current_repository.commits.find(check_suite.head_sha)
    rescue GitRPC::ObjectMissing
      render_404 and return
    end

    all_annotations = find_latest_annotations(workflow_run, execution: execution)
    gate_requests = find_gate_requests(check_suite)
    gate_approval_logs = check_suite.gate_approval_logs_for_execution(execution: execution)

    workflow_job_runs = workflow_run.latest_workflow_job_runs(execution: execution).where.not(summary_url: [nil, ""])

    retry_blankstate = !!(!attempt.present? && execution&.is_latest_execution? && workflow_run&.processing_retry?)

    respond_to do |format|
      format.html do
        render "actions/workflow_runs/show", locals: {
          selected_check_suite: check_suite,
          selected_check_run: nil,
          commit: commit,
          workflows_loading: false,
          all_annotations: all_annotations,
          gate_requests: gate_requests,
          gate_approval_logs: gate_approval_logs,
          show_spammy_warning: show_spammy_warning,
          show_check_run_logs: true,
          execution: execution,
          workflow_job_runs: workflow_job_runs,
          retry_blankstate: retry_blankstate,
          green_trees_enabled: feature_enabled_globally_or_for_current_user?(:actions_green_trees),
          can_view_workflow_file: can_view_workflow_file?(workflow_run),
          can_show_copilot_button: false
        }
      end
    end

    # mark workflow completed/failed and approval notifications as read
    async_mark_threads_as_read [check_suite, workflow_run]
  end

  def usage # rubocop:todo GitHub/UseRestfulActions
    workflow_run = find_workflow_run
    return render_404 unless workflow_run

    begin
      commit = current_repository.commits.find(workflow_run.check_suite.head_sha)
    rescue GitRPC::ObjectMissing
      render_404 and return
    end

    latest_execution = find_latest_execution(workflow_run)
    retry_blankstate = !!(latest_execution.present? && workflow_run&.processing_retry?)

    render "actions/workflow_runs/usage", locals: {
      workflow_run: workflow_run,
      commit: commit,
      latest_execution: latest_execution,
      retry_blankstate: retry_blankstate,
      can_view_workflow_file: can_view_workflow_file?(workflow_run)
    }
  end

  def workflow_file # rubocop:todo GitHub/UseRestfulActions
    workflow_run = find_workflow_run
    return render_404 unless workflow_run
    return render_404 unless can_view_workflow_file?(workflow_run)

    begin
      commit = current_repository.commits.find(workflow_run.check_suite.head_sha)
    rescue GitRPC::ObjectMissing
      render_404 and return
    end

    annotations = workflow_run.check_suite&.annotations.where(path: workflow_run.check_suite.workflow_file_path) || []
    latest_execution = find_latest_execution(workflow_run)
    retry_blankstate = !!(latest_execution.present? && workflow_run&.processing_retry?)

    render "actions/workflow_runs/workflow_file", locals: {
      workflow_run: workflow_run,
      commit: commit, annotations: annotations,
      latest_execution: latest_execution,
      retry_blankstate: retry_blankstate,
      can_view_workflow_file: true
    }
  end

  def workflow_run_summary_partial # rubocop:todo GitHub/UseRestfulActions
    return head :not_found unless request.xhr?

    workflow_run = find_workflow_run
    return render_404 unless workflow_run

    begin
      commit = current_repository.commits.find(workflow_run.check_suite.head_sha)
    rescue GitRPC::ObjectMissing
      render_404 and return
    end

    execution = find_latest_execution(workflow_run)
    retry_blankstate = !!(execution.present? && workflow_run.processing_retry?)

    render Actions::WorkflowRuns::SummaryBarComponent.new(
      check_suite: workflow_run.check_suite,
      commit: commit,
      current_repository: current_repository,
      execution: execution,
      retry_blankstate: retry_blankstate
    ), layout: false
  end

  # temporary redirct to smooth over shipping route rename
  def sidebar_partial # rubocop:todo GitHub/UseRestfulActions
    redirect_to workflow_run_navigation_partial_path(workflow_run_id: params[:workflow_run_id], selected_check_run_id: params[:selected_check_run_id], selected_tab: params[:selected_tab])
  end

  # Sidebar live updates. Mobile nav initial load and live updates
  def navigation_partial # rubocop:todo GitHub/UseRestfulActions
    return head :not_found unless request.xhr?

    workflow_run = find_workflow_run
    return render_404 unless workflow_run

    execution = params[:attempt].present? ? workflow_run.workflow_run_executions.find_by!(attempt: params[:attempt]) : find_latest_execution(workflow_run)

    selected_check_run = Checks.domain.check_runs.for_id(params[:selected_check_run_id].to_i, repository_id: workflow_run.repository_id) if params[:selected_check_run_id]

    render Actions::WorkflowRuns::NavigationComponent.new(
      check_suite: workflow_run.check_suite,
      selected_check_run: selected_check_run,
      current_repository: current_repository,
      selected_tab: params[:selected_tab]&.to_sym,
      execution: execution,
      pull_request_number: params[:pr],
      can_view_workflow_file: can_view_workflow_file?(workflow_run)
    ), layout: false
  end

  # Used for live updates for the annotations view component
  def annotations_partial # rubocop:todo GitHub/UseRestfulActions
    return head :not_found unless request.xhr?

    workflow_run = find_workflow_run
    return render_404 unless workflow_run

    begin
      commit = current_repository.commits.find(workflow_run.check_suite.head_sha)
    rescue GitRPC::ObjectMissing
      render_404 and return
    end

    all_annotations = find_latest_annotations workflow_run

    render Actions::WorkflowRuns::AnnotationsComponent.new(
      workflow_run: workflow_run,
      current_repository: current_repository,
      commit: commit,
      annotations: all_annotations
    ), layout: false
  end

  # Used for live updates for the new header
  def header_partial # rubocop:todo GitHub/UseRestfulActions
    return head :not_found unless request.xhr?

    workflow_run = find_workflow_run
    return render_404 unless workflow_run

    begin
      commit = current_repository.commits.find(workflow_run.check_suite.head_sha)
    rescue GitRPC::ObjectMissing
      render_404 and return
    end

    selected_check_run = workflow_run.check_suite.check_runs.find_by_id(params[:selected_check_run_id].to_i)
    execution = find_latest_execution(workflow_run)
    retry_blankstate = !!(execution.present? && workflow_run.processing_retry?)

    render Actions::WorkflowRuns::HeaderComponent.new(
      check_suite: workflow_run.check_suite,
      commit: commit,
      current_repository: current_repository,
      selected_check_run: selected_check_run,
      selected_tab: params[:selected_tab],
      execution: execution,
      retry_blankstate: retry_blankstate
    ), layout: false
  end

  def graph_partial # rubocop:todo GitHub/UseRestfulActions
    return head :not_found unless request.xhr?

    workflow_run = find_workflow_run_with_graph
    return render_404 unless workflow_run

    execution = find_execution_with_graph(workflow_run)
    retry_blankstate = !!(execution.present? && workflow_run.processing_retry?)

    render Actions::Graph::GraphComponent.new(
      graph: workflow_run.graph(execution: execution, include_deployments: true),
      workflow_run: workflow_run,
      execution: execution,
      retry_blankstate: retry_blankstate,
      pull_request_number: params[:pr],
    ), layout: false
  end

  def rerequest_check_suite # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless current_user_can_push?

    workflow_run = find_workflow_run
    return render_404 unless workflow_run

    begin
      check_run = Checks.domain.check_runs.for_id(params[:check_run_id].to_i, repository_id: current_repository.id) if params[:check_run_id]

      if check_run
        check_run.actions_rerequest(actor: current_user, enable_debug_logging: params[:enable_debug_logging] == "true")
      else
        workflow_run.check_suite.rerequest(actor: current_user, only_failed_check_runs: params[:only_failed_check_runs] == "true", enable_debug_logging: params[:enable_debug_logging] == "true")
      end
    rescue CheckSuite::ActionsDependency::ExpiredWorkflowRunError
      flash[:error] = "Unable to re-run this workflow because it was created over a month ago."
      redirect_to :back and return
    rescue CheckSuite::AlreadyRerunningError
      flash[:error] = "This workflow is already running."
      redirect_to :back and return
    rescue CheckSuite::DisabledWorkflowError
      flash[:error] = "Unable to re-run disabled workflow."
      redirect_to :back and return
    rescue CheckSuite::ExpiredLogsError
      flash[:error] = "Unable to re-run workflow with expired logs."
      redirect_to :back and return
    rescue CheckSuite::NotRerequestableError
      flash[:error] = "Unable to re-run workflow."
      redirect_to :back and return
    end

    redirect_to workflow_run_path(workflow_run, user_id: current_repository.owner, repository: current_repository, pr: params[:pr])
  end

  # Used for live updates for action required banner
  def action_required_partial # rubocop:todo GitHub/UseRestfulActions
    return head :not_found unless request.xhr?

    workflow_run = find_workflow_run
    return render_404 unless workflow_run

    render Actions::WorkflowRuns::ActionRequiredComponent.new(
      check_suite: workflow_run.check_suite,
      current_repository: current_repository
    ), layout: false
  end

  # Used for live updates for the approvals view
  def approvals_partial # rubocop:todo GitHub/UseRestfulActions
    return head :not_found unless request.xhr?

    workflow_run = find_workflow_run
    return render_404 unless workflow_run

    execution = find_latest_execution(workflow_run)
    approval_logs = workflow_run.check_suite.gate_approval_logs_for_execution(execution: execution)

    gate_approval_logs = approval_logs.includes(:user, gate_approvals: [{ gate_request: [{ gate: :integration }] }, :environment]).to_a

    render Actions::Environments::DeploymentProtectionLogComponent.new(
      check_suite: workflow_run.check_suite,
      gate_approval_logs: gate_approval_logs,
      should_update: true,
      execution: execution,
    ), layout: false
  end

  def approvals_banner_partial # rubocop:todo GitHub/UseRestfulActions
    return head :not_found unless request.xhr?
    workflow_run = find_workflow_run
    return render_404 unless workflow_run

    if current_repository.adminable_by?(current_user) && current_repository.can_use_environments?
      gate_requests = pending_gate_requests(workflow_run.check_suite)
    else
      gate_requests = []
    end

    render Actions::Environments::ApprovalsBannerComponent.new(
      workflow_run: workflow_run,
      pending_gate_requests: gate_requests,
      approval_path: approve_or_reject_gate_requests_url
    ), layout: false
  end

  def concurrency_banner_partial # rubocop:todo GitHub/UseRestfulActions
    return head :not_found unless request.xhr?

    workflow_run = find_workflow_run
    return render_404 unless workflow_run

    render Actions::WorkflowRuns::ConcurrencyBannerComponent.new(
      check_suite: workflow_run.check_suite,
      should_update: true
    ), layout: false
  end

  # Used for live updates for the artifacts component
  def artifacts_partial # rubocop:todo GitHub/UseRestfulActions
    return head :not_found unless request.xhr?

    workflow_run = find_workflow_run
    return render_404 unless workflow_run

    render Actions::WorkflowRuns::ArtifactsComponent.new(
      check_suite: workflow_run.check_suite, current_repository: current_repository
    ), layout: false
  end

  def delete_logs # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless current_user_can_push?

    workflow_run = find_workflow_run
    return render_404 unless workflow_run

    begin
      workflow_run.delete_logs(actor: current_user)
      flash[:notice] = "Logs deleted successfully."
    rescue RuntimeError
      flash[:error] = "Failed to delete the logs for this workflow run."
    end

    path = workflow_run_path(workflow_run, user_id: current_repository.owner, repository: current_repository)
    redirect_to path
  end

  def delete_workflow_run # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless current_user_can_push?

    workflow_run = find_workflow_run
    return render_404 unless workflow_run

    begin
      workflow = workflow_run.workflow
      workflow_run.hard_delete(actor: current_user)
      flash[:notice] = "Workflow run deleted successfully."
      if workflow && workflow.required?
        workflow.delete if workflow.workflow_runs.empty?
      end
    rescue Actions::WorkflowRun::NotDeleteableError, ActiveRecord::RecordInvalid
      flash[:error] = "Failed to delete this workflow run."
    end

    redirect_to :back
  end

  # Used to render a list of pull requests that may not be able to be merged if a workflow run is deleted
  def delete_pull_requests_list # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless request.xhr?

    workflow_run = find_workflow_run
    return render_404 unless workflow_run

    pull_requests = current_repository.pull_requests.where(
      head_sha: workflow_run.head_sha,
      head_repository_id: workflow_run.check_suite.head_repository_id,
    )

    respond_to do |format|
      format.html do
        render partial: "actions/workflow_run_item_delete_pull_requests_list", locals: {
          pull_requests: pull_requests
        }
      end
    end
  end

  def disable_workflow # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless current_user_can_push?

    workflow = find_workflow
    return render_404 unless workflow
    return render_404 unless workflow.disableable?

    begin
      workflow.disable(current_user)
      flash[:notice] = "Workflow disabled successfully."
    rescue Actions::Workflow::NotActiveError
      flash[:error] = "Unable to disable a workflow that is not active."
    end

    redirect_to :back
  end

  def enable_workflow # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless current_user_can_push?

    workflow = find_workflow
    return render_404 unless workflow

    begin
      workflow.enable(current_user)
      flash[:notice] = "Workflow enabled successfully."
    rescue Actions::Workflow::CannotBeEnabledError
      flash[:error] = "Unable to enable a workflow that is not active."
    end

    redirect_to :back
  end

  def job_steps # rubocop:todo GitHub/UseRestfulActions
    workflow_run = find_workflow_run
    return render_404 unless workflow_run

    workflow_job_run = find_workflow_job_run(workflow_run, params[:job_id])
    return render_404 unless workflow_job_run

    change_id = params[:change_id].to_i
    check_run = workflow_job_run.check_run
    steps = check_run.steps_from_backend(change_id)

    steps_hash = steps.map do |step|
      log_url = check_step_logs_path(ref: workflow_run.commit.oid, id: check_run.id, step: step.number) if step.completed_log_url.present?

      {
        id:                  step.external_id,
        name:                step.name,
        status:              step.status,
        conclusion:          step.conclusion,
        number:              step.number,
        started_at:          step.started_at,
        completed_at:        step.completed_at,
        change_id:           step.change_id || 0,
        completed_log_lines: step.completed_log_lines,
        completed_log_url:   step.completed_log_url,
        log_url:             log_url
      }
    end

    headers["Cache-Control"] = "no-store, max-age=0"
    render json: steps_hash
  end

  def job_step_backscroll # rubocop:todo GitHub/UseRestfulActions
    workflow_run = find_workflow_run
    return render_404 unless workflow_run

    workflow_job_run = find_workflow_job_run(workflow_run, params[:job_id])
    return render_404 unless workflow_job_run

    step_backscroll = workflow_job_run.check_run.get_log_scrollback_from_results(params[:step_external_id])

    headers["Cache-Control"] = "no-store, max-age=0"
    render json: step_backscroll
  end

  def job_summary_content # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless logged_in?

    workflow_run = find_workflow_run
    return render_404 unless workflow_run

    workflow_job_run = find_workflow_job_run(workflow_run, params[:job_id])
    return render_404 unless workflow_job_run

    return render_404 unless workflow_job_run.summary_url.present?

    respond_to do |format|
      format.html do
        render Actions::WorkflowRuns::JobSummaryContentComponent.new(
          check_suite: workflow_run.check_suite,
          workflow_job_run: workflow_job_run,
          preload: true
        ), layout: false
      end
    end
  end

  def job_summary_raw # rubocop:todo GitHub/UseRestfulActions
    # override request format so we have plain text responses
    request.format = :plain
    return render_404 unless logged_in?

    workflow_run = find_workflow_run
    return render_404 unless workflow_run

    workflow_job_run = find_workflow_job_run(workflow_run, params[:job_id])
    return render_404 unless workflow_job_run

    return render_404 unless workflow_job_run.summary_url.present?

    job_summary = workflow_job_run.get_summary
    return render_404 unless job_summary

    render plain: job_summary.step_summaries.map { |step| step[:content] }.join("\n")
  end

  def job_summary_partial # rubocop:todo GitHub/UseRestfulActions
    return head :not_found unless request.xhr?

    return render_404 unless logged_in?

    workflow_run = find_workflow_run
    return render_404 unless workflow_run

    execution = find_latest_execution(workflow_run)
    workflow_job_runs = workflow_run.latest_workflow_job_runs(execution: execution).where.not(summary_url: [nil, ""])

    render Actions::WorkflowRuns::JobSummariesComponent.new(
      current_repository: current_repository,
      current_user: current_user,
      check_suite: workflow_run.check_suite,
      workflow_job_runs: workflow_job_runs.includes(:check_run),
      execution: execution,
      # the partial is rendered in the instances where a user is "waiting" on the summary page while the job is
      # in progress. to prevent jobs from "unloading" depending on their ordering, we'll just load all of them
      preload_all: true,
    ), layout: false
  end

  def attempts # rubocop:todo GitHub/UseRestfulActions
    workflow_run = find_workflow_run
    return render_404 unless workflow_run

    current_attempt = params[:current_attempt_number]
    return render_404 unless current_attempt.present?

    retry_blankstate = params[:retry_blankstate].downcase == "true"

    attempt_objects = create_attempt_objects(
      workflow_run,
      retry_blankstate,
      current_attempt,
      pull_request_number: params[:pr]
    )

    render "actions/workflow_runs/attempts",
      layout: false,
      locals: {
        attempt_objects: attempt_objects,
      }
  end

  # Used to render the attempt navigation menu behind flag `actions_new_attempts_menu`
  def new_attempts_menu # rubocop:todo GitHub/UseRestfulActions
    workflow_run = find_workflow_run
    return render_404 unless workflow_run

    current_attempt = params[:current_attempt_number]
    return render_404 unless current_attempt.present?

    retry_blankstate = params[:retry_blankstate].downcase == "true"

    attempt_objects = create_attempt_objects(
      workflow_run,
      retry_blankstate,
      current_attempt,
      pull_request_number: params[:pr]
    )

    render "actions/workflow_runs/new_attempts_menu",
      layout: false,
      locals: {
        attempt_objects: attempt_objects,
      }
  end

  def failed_jobs # rubocop:todo GitHub/UseRestfulActions
    workflow_run = find_workflow_run_with_graph
    return render_404 unless workflow_run

    failed_jobs = workflow_run.failed_workflow_job_runs
    downstream_jobs = workflow_run.downstream_jobs_for(jobs: failed_jobs)
    check_runs = failed_jobs.concat(downstream_jobs).uniq.map { |job_run| job_run.check_run }

    render partial: "actions/workflow_runs/rerun_jobs_list", locals: { check_runs: check_runs }
  end

  def job_downstream_list # rubocop:todo GitHub/UseRestfulActions
    workflow_run = find_workflow_run_with_graph
    return render_404 unless workflow_run

    workflow_job_run = find_workflow_job_run(workflow_run, params[:job_id])
    return render_404 unless workflow_job_run

    downstream_jobs = workflow_run.downstream_jobs_for(jobs: [workflow_job_run])
    check_runs = [workflow_job_run].concat(downstream_jobs).map { |job_run| job_run.check_run }

    render partial: "actions/workflow_runs/rerun_jobs_list", locals: { check_runs: check_runs }
  end

  def jobs_list # rubocop:todo GitHub/UseRestfulActions
    workflow_run = find_workflow_run
    return render_404 unless workflow_run

    check_runs = workflow_run.latest_check_runs.select(&:is_actions_check_run?).sort_by(&:sort_order)
    render partial: "actions/workflow_runs/rerun_jobs_list", locals: { check_runs: check_runs }
  end

  def job_rerun_dialogs_partial # rubocop:todo GitHub/UseRestfulActions
    workflow_run = find_workflow_run
    return render_404 unless workflow_run

    render Actions::WorkflowRuns::JobRerunDialogsContainerComponent.new(
      current_repository: current_repository,
      workflow_run: workflow_run,
    ), layout: false
  end

  def download_artifact # rubocop:todo GitHub/UseRestfulActions
    workflow_run = find_workflow_run
    return render_404 unless workflow_run

    redirect_to download_artifact_path(id: workflow_run.check_suite.id, user_id: current_repository.owner, repository: current_repository, artifact_id: params[:artifact_id]), status: 307
  end

  private

  def find_workflow_run
    workflow_run = Actions::WorkflowRun.find_by(id: params[:workflow_run_id])
    if !workflow_run || is_missing_check_suite(workflow_run) || workflow_run.check_suite.repository_id != current_repository.id
      return nil
    end
    workflow_run
  end

  def find_workflow_run_with_graph
    workflow_run = Actions::WorkflowRun.with_execution_graph.find_by(id: params[:workflow_run_id])
    if !workflow_run || is_missing_check_suite(workflow_run) || workflow_run.check_suite.repository_id != current_repository.id
      return nil
    end
    workflow_run
  end

  def is_missing_check_suite(workflow_run)
    if workflow_run.check_suite.nil?
      GitHub.logger.info(
        "Workflow run without checksuite",
        {
          "gh.catalog_service" => "github/actions",
          "code.namespace" => "Actions::WorkflowRunsController",
          "code.function" => "is_missing_check_suite",
          "gh.repo.id" => current_repository.id,
          "gh.workflow_run.id" => workflow_run.id,
        }
      )

      true
    end
  end

  def find_execution_attempt_with_graph!(workflow_run, attempt)
    Actions::WorkflowRunExecution.unscoped { workflow_run.workflow_run_executions.find_by!(attempt: attempt) }
  end

  # returns nil the workflow run does not have executions
  def find_latest_execution(workflow_run)
    workflow_run.latest_workflow_run_execution
  end

  def find_execution_with_graph(workflow_run)
    workflow_run.latest_workflow_run_execution_with_graph
  end

  def find_workflow
    workflow = Actions::Workflow.find_by(id: params[:workflow_id])
    if !workflow || workflow.repository_id != current_repository.id
      return nil
    end
    workflow
  end

  def find_gate_requests(check_suite)
    return [] unless current_repository.can_use_environments?
    pending_gate_requests(check_suite)
  end

  def find_latest_annotations(workflow_run, execution: nil)
    check_suite = workflow_run.check_suite
    check_run_ids = workflow_run.latest_check_runs(execution: execution).pluck(:id)

    if execution.present?
      check_suite_annotations = check_suite.annotations.where("created_at BETWEEN ? and ?", execution.started_at || execution.created_at, execution.completed_at || DateTime.now).limit(CheckAnnotation::MAX_READ_LIMIT)
      check_run_annotations = CheckAnnotation
        .includes(:check_run)
        .where(repository: workflow_run.repository)
        .where("check_run_id in (?)", check_run_ids)
        .limit(CheckAnnotation::MAX_READ_LIMIT)
    else
      check_suite_annotations = check_suite.annotations.where("created_at >= ?", check_suite.started_at || check_suite.created_at)
      check_run_annotations = CheckAnnotation
        .includes(:check_run)
        .where(repository: workflow_run.repository)
        .where("check_run_id in (?)", check_run_ids)
        .limit(CheckAnnotation::MAX_READ_LIMIT)
    end

    check_run_annotations.to_a + check_suite_annotations.to_a
  end

  def find_workflow_job_run(workflow_run, workflow_job_run_id)
    workflow_run.workflow_job_runs.find_by_id(workflow_job_run_id)
  end

  def create_attempt_objects(workflow_run, retry_blankstate, current_attempt, pull_request_number: nil)
    workflow_run_executions = workflow_run.workflow_run_executions.reorder(attempt: :desc).includes(:actor).to_a
    current_execution = workflow_run.workflow_run_executions.find_by(attempt: params[:current_attempt_number], repository: current_repository)

    if retry_blankstate
      # do not render "latest attempt" object because the execution does not exist yet
      other_executions = workflow_run_executions
    else
      latest_execution = workflow_run_executions.first
      other_executions = workflow_run_executions.drop(1)
    end

    datetime_format = "%b %d"

    latest = {
      title: "Latest attempt ##{latest_execution.attempt}",
      conclusion: latest_execution.conclusion,
      status: latest_execution.status,
      actor_login: latest_execution.actor&.display_login,
      time: latest_execution.completed? ? latest_execution.completed_at&.strftime(datetime_format) : latest_execution.started_at&.strftime(datetime_format),
      attempt_number: latest_execution.attempt,
      path: workflow_run_path(
        user_id: current_repository.owner_display_login,
        repository: current_repository,
        workflow_run_id: workflow_run.id,
        pr: pull_request_number
      ),
      verb_state: latest_execution.completed? ? StatusCheckConfig.verb_state(latest_execution.conclusion) : latest_execution.status.humanize(capitalize: false),
      selected: current_execution.id == latest_execution.id,
    } if latest_execution.present?

    others = other_executions.map do |execution|
      {
        title: "Attempt ##{execution.attempt}",
        conclusion: execution.conclusion,
        status: execution.status,
        actor_login: execution.actor&.display_login,
        time: execution.completed_at&.strftime(datetime_format),
        attempt_number: execution.attempt,
        path: workflow_run_attempt_path(workflow_run_id: workflow_run.id, repository: current_repository, user_id: current_repository.owner.display_login, attempt: execution.attempt, pr: pull_request_number),
        verb_state: StatusCheckConfig.verb_state(execution.conclusion),
        selected: current_execution.id == execution.id && !retry_blankstate,
      }
    end

    return [latest] + others if latest.present?
    others
  end

  def route_supports_advisory_workspaces?
    parent_repository_can_have_actions_on_private_forks? || super
  end

  def can_view_workflow_file?(workflow_run)
    workflow_run&.can_user_view_workflow_file?(current_user)
  end
end
