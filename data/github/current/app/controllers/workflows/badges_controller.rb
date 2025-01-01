# typed: true
# frozen_string_literal: true

class Workflows::BadgesController < AbstractRepositoryController
  include ActionsControllerMethods

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Spokes,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::RepositoriesActionsChecks,
    only: [:configure_by_file]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Spokes,
    only: [:show_by_file]

  CONDITIONAL_ACCESS_BYPASS_PUBLIC_REPO_ACTIONS = %w(show).freeze

  around_action :track_and_report_render_view_time, only: [:show, :show_by_file]

  before_action :actions_enabled?
  before_action :workflow_name_given?, only: [:show]
  before_action :workflow_filename_given?, except: [:show]

  def show_by_file # rubocop:todo GitHub/UseRestfulActions
    is_lab = params[:lab] == "true"
    workflow = current_repository.workflows.find_from_filename(params[:workflow_filename], is_lab: is_lab)
    return render_404 unless workflow

    if show_only_required_workflows?
      return render_404 unless workflow.required?
    end
    filtered_to_branch = params.has_key?(:branch)
    head_branch = params[:branch] || current_repository.default_branch

    # If an event has been passed in, only get runs triggered by that
    filtered_to_event = params.has_key?(:event)
    event = params[:event]

    # Try to get the latest run for the given workflow, branch, and event
    latest_run = most_recent_run_for_workflow(workflow, head_branch: head_branch, event: event, is_lab: is_lab)

    if !latest_run && !filtered_to_branch
      # Check if there are runs for *any* branch if no branch was requested
      latest_run = most_recent_run_for_workflow(workflow, event: event, is_lab: is_lab)
    end

    state = latest_run&.conclusion || latest_run&.status

    respond_to do |format|
      format.svg do
        headers["Cache-Control"] = "max-age=300, private"
        render "workflows/badges/show",
          locals: { workflow: workflow.name, state: state }
      end
    end
  end

  def configure_by_file # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless request.xhr?

    is_lab = params[:lab] == "true"
    workflow = current_repository.workflows.find_from_filename(params[:workflow_filename], is_lab: is_lab)
    return render_404 unless workflow

    if show_only_required_workflows?
      return render_404 unless workflow.required?
    end

    path_params = {
      workflow_filename: workflow.filename,
      branch: params[:branch].presence,
      event: params[:event].presence,
      lab: params[:lab].presence,
      repository: current_repository,
      user_id: current_repository.owner.display_login,
    }

    configure_path = workflow_badge_by_file_configure_path(path_params)
    badge_path = workflow_badge_by_file_path(path_params)
    badge_url = workflow_badge_by_file_url(path_params)
    respond_to do |format|
      format.html do
        render partial: "workflows/badges/configure_form_branch_select_panel", locals: {
          workflow_name: workflow.name,
          branch: params[:branch],
          event: params[:event],
          configure_path: configure_path,
          badge_path: badge_path,
          badge_url: badge_url,
          workflow_url: workflow_runs_list_url(workflow_file_name: workflow.filename),
        }
      end
    end
  end

  # This is a legacy, undocumented version of the badge API. Please use show_by_file instead.
  def show
    workflow_name = Actions::Workflow.decode_url_safe_name(params[:workflow_name])

    is_lab = params[:lab] == "true"
    app_id = GitHub.launch_github_app.id
    if is_lab
      app_id = GitHub.launch_lab_github_app&.id
    end

    filtered_to_branch = params.has_key?(:branch)
    head_branch = params[:branch] || current_repository.default_branch

    # If an event has been passed in, only get runs triggered by that
    filtered_to_event = params.has_key?(:event)
    event = params[:event]

    # Try to get the latest run for the given workflow, branch, and event
    latest_run = most_recent_run_for(app_id: app_id, workflow_name: workflow_name, head_branch: head_branch, event: event)

    if !latest_run && !filtered_to_branch && !filtered_to_event
      # Check if there are runs for *any* branch and event, if no branch and no event was requested
      latest_run = most_recent_run_for(
        app_id: app_id,
        workflow_name: workflow_name
      )
    end

    if !latest_run
      # Check if the workflow exists at all
      workflows = current_repository.workflows.active
      workflows = params[:lab] == "true" ? workflows.lab : workflows.prod
      return render_404 unless workflows.find_by(name: workflow_name)
    end

    # At this point we either do have a run, or we at least know that the workflow exists,
    # and can show the no-status badge.
    state = latest_run&.conclusion || latest_run&.status

    respond_to do |format|
      format.svg do
        headers["Cache-Control"] = "max-age=300, private"
        render "workflows/badges/show",
          locals: { workflow: workflow_name, state: state }
      end
    end
  end

  private

  def most_recent_run_for_workflow(workflow, head_branch: nil, event: nil, is_lab: false)
    query = head_branch.nil? ? "" : "branch:\"#{head_branch}\""
    query = "#{query} event:\"#{event}\"" if event
    latest_runs = Actions::WorkflowRun.search(
      query: query,
      workflow_id: workflow.id,
      repo: current_repository,
      head_repo_id: current_repository.id,
      unsupported_conclusions: Workflows::BadgeComponent::UNSUPPORTED_CONCLUSIONS,
      is_lab: is_lab,
      sort: %w[workflow_run_id desc]
    )

    latest_runs[:workflow_runs].first
  end

  def most_recent_run_for(app_id:, workflow_name:, head_branch: nil, event: nil)
    latest_runs = CheckSuite
      .from("check_suites FORCE INDEX(by_repo_app_and_name)")
      .for_app_id(app_id)
      .where(repository_id: current_repository.id)
      .for_workflow(workflow_name)
      .where(conclusion: Workflows::BadgeComponent::SUPPORTED_CONCLUSIONS, head_repository: current_repository)
      .most_recent

    latest_runs = latest_runs.where(head_branch: head_branch) if head_branch
    latest_runs = latest_runs.where(event: event) if event
    latest_runs.first
  end

  def actions_enabled?
    render_404 unless GitHub.actions_enabled?
  end

  def workflow_name_given?
    render_404 unless params[:workflow_name]
  end

  def workflow_filename_given?
    render_404 unless params[:workflow_filename]
  end
end
