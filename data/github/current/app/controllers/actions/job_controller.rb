# typed: false
# frozen_string_literal: true

class Actions::JobController < AbstractRepositoryController
  include ControllerMethods::CheckAnnotations

  helper_method :use_actions_ux?
  stylesheet_bundle :actions

  before_action :all_color_mode_themes

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Spokes,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Spokes,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    ApplicationRecord::RepositoriesPushes,
    ApplicationRecord::Iam,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :show], optional: true

  def show
    return render_404 if request.xhr?

    workflow_run = Actions::WorkflowRun.includes(:check_suite).find_by(id: params[:workflow_run_id], repository_id: current_repository.id)
    if workflow_run.nil?
      render_404 and return
    end

    check_suite = workflow_run.check_suite
    if check_suite.nil?
      render_404 and return
    end

    workflow_job_run = Actions::WorkflowJobRun.includes(:check_run).find_by(id: params[:job_id], repository_id: current_repository.id, workflow_run_id: workflow_run.id)
    if workflow_job_run.nil?
      render_404 and return
    end

    check_run = workflow_job_run.check_run
    if check_run.nil?
      render_404 and return
    end

    redirect_to actions_job_path(workflow_run_id: params[:workflow_run_id], job_id: check_run.id, pr: params[:pr])
  end

  # There are two main routes due to historical reasons with the check_run_id being used in APIs and webhook payloads
  # See https://github.com/github/c2c-actions/blob/main/docs/adrs/7143-workflow-job-web-url.md
  def index
    return render_404 if request.xhr?

    workflow_run = Actions::WorkflowRun.includes(:check_suite).find_by(id: params[:workflow_run_id], repository_id: current_repository.id)
    if workflow_run.nil?
      render_404 and return
    end

    check_suite = workflow_run.check_suite
    if check_suite.nil?
      render_404 and return
    end

    check_run = CheckRun.includes(:workflow_job_run).find_by(id: params[:job_id], repository_id: current_repository.id)
    if check_run.nil? || check_run.check_suite_id != check_suite.id
      render_404 and return
    end

    workflow_job_run = check_run.workflow_job_run
    if workflow_job_run.nil?
      render_404 and return
    end

    head_sha = check_suite.head_sha
    unless current_repository.commits.exist?(head_sha)
      render_404 and return
    end

    commit = current_repository.commits.find(head_sha)

    if check_run.is_actions_check_run?
      render "actions/workflow_runs/show",
      layout: "repository",
      locals: {
        commit: commit,
        selected_check_run: check_run,
        blankslate: false,
        show_check_run_logs: true,
        execution: workflow_job_run.workflow_run_execution,
        retry_blankstate: false,
        can_view_workflow_file: can_view_workflow_file?(workflow_run),
        can_show_copilot_button: can_show_copilot_button?
      }
    else
      # Check runs can be manually created using GITHUB_TOKEN and the view is slightly different compared to normal Actions check runs
      # Long term we would like to restrict these types of check runs from being created but for now this is still supported
      annotation_details = load_annotation_details(check_run: check_run)

      render "actions/workflow_runs/show",
      layout: "repository",
      locals: {
        commit: commit,
        selected_check_run: check_run,
        blankslate: false,
        annotation_details: annotation_details,
        show_check_run_logs: true,
        execution: workflow_job_run.workflow_run_execution,
        retry_blankstate: false,
        can_view_workflow_file: can_view_workflow_file?(workflow_run),
        can_show_copilot_button: false
      }
    end
  end

  protected

  # Protected rather than private for stubbability
  def can_show_copilot_button?
    feature_enabled_globally_or_for_user?(feature_name: :copilot_chat_job_logs_ui) &&
      feature_enabled_globally_or_for_user?(feature_name: "copilot-api-skills-get-run-logs".to_sym) &&
      with_database_error_fallback(fallback: false) do
        helpers.copilot_chat_enabled_for_current_user? && current_copilot_user_v2.beta_features_github_chat_enabled?
      end
  end

  private

  # This is currently needed because a bunch of older checks templates (such as checks_steps_container.html.erb) call this method. Long term we should remove this
  def use_actions_ux?
    true
  end

  def route_supports_advisory_workspaces?
    parent_repository_can_have_actions_on_private_forks? || super
  end

  def can_view_workflow_file?(workflow_run)
    # required workflows have an imposer repo id
    # if the workflow is required, check that the user has pull access to source repo

    workflow_valid = workflow_run&.workflow_file_path.present? && !workflow_run&.dynamic_workflow?
    source_repo_id = workflow_run&.imposer_repository_id

    return workflow_valid unless source_repo_id && source_repo_id > 0

    T.cast(Repositories.domain.by_id(source_repo_id), Repository).pullable_by?(current_user) # rubocop:disable GitHub/AvoidCast
  end

end
