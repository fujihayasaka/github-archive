# typed: true
# frozen_string_literal: true

class DeployFormController < AbstractRepositoryController
  include WebCommitControllerMethods
  include ApplicationController::VerifiedFetchDependency

  allow_verified_fetch only: [:cancel_deployment, :start_deploy]

  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = %w[
    DeployFormController#cancel_deployment
    DeployFormController#start_deploy
  ].freeze

  # Declare cluster dependencies based on what this controller needs
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::ActionsEnvironments,
    ApplicationRecord::Permissions,
    ApplicationRecord::Lodge,
    only: [:show, :index, :workflow_run_status, :cancel_deployment, :start_deploy]

  before_action :require_feature_flags

  layout "layouts/repository_with_container"

  DEPLOY_WORKFLOW_FILENAME = "deploy.yml"

  def show
    workflow_file_path = ".github/workflows/#{DEPLOY_WORKFLOW_FILENAME}"
    branch = current_repository.default_branch

    # Get framework and package manager from URL params
    framework = params[:framework]
    package_manager = params[:package_manager]

    # Check if the workflow file already exists in the repository
    file_exists = current_repository.includes_file?(workflow_file_path, branch)

    if file_exists
      save_url = file_save_path(current_repository.owner, current_repository, branch, workflow_file_path)
    else
      save_url = blob_create_path(workflow_file_path, branch, current_repository)
    end

    # Set @last_commit to the latest commit oid on the default branch
    set_form_commit(!file_exists)

    commit_info = web_commit_info(@last_commit, save_url, branch)

    respond_with_react(
      title: "Deploy · #{current_repository.name_with_display_owner}",
      payload: DeployFormPayload.new(
        workflow_file_path: workflow_file_path,
        commit_info: commit_info,
        branch: branch,
        framework: framework,
        package_manager: package_manager
      )
    )
  end

  def index
    # Find the deploy workflow specifically
    workflow = current_repository.workflows.not_deleted.find_from_id_or_filename(DEPLOY_WORKFLOW_FILENAME)

    return head :not_found unless workflow

    workflow_runs = workflow.workflow_runs
      .most_recent
      .where(user_hidden: false)
      .limit(params[:per_page]&.to_i || 30)
      .offset(params[:page]&.to_i&.*(params[:per_page]&.to_i || 30) || 0)

    respond_to do |format|
      format.json do
        render json: {
          workflow_runs: workflow_runs.map do |run|
            {
              id: run.id,
              created_at: run.created_at,
              workflow_id: run.workflow_id,
              status: run.status,
            }
          end,
        }
      end
    end
  end

  def start_deploy # rubocop:todo GitHub/UseRestfulActions
    # Verify user has write access to start deployments
    unless current_repository.writable_by?(current_user)
      return render json: {
        error: "You do not have permission to start deployments in this repository."
      }, status: :forbidden
    end

    # Verify user's plan supports Pages for private repositories
    if current_repository.private? && !current_repository.plan_supports_pages?
      return render json: {
        error: "Your current plan does not support GitHub Pages for private repositories."
      }, status: :unprocessable_entity
    end

    # Enable Actions app when deployment is kicked off - required for workflow-based deployments
    unless current_repository.actions_app_installed?
      # Enabling Actions requires elevated permissions (actions settings access)
      unless current_repository.can_write_repository_actions_settings?(current_user)
        return render json: {
          error: "You do not have permission to enable Actions for this repository."
        }, status: :forbidden
      end

      if GitHub.launch_github_app.present?
        result = current_repository.enable_actions_app(
          actor: current_user,
          entry_point: :deploy_form_controller_start_deploy
        )

        unless result.success?
          return render json: { success: false, error: "Unable to enable Actions for this repository." },
            status: :unprocessable_entity
        end
      end
    end

    render json: { success: true }
  end

  def cancel_deployment # rubocop:todo GitHub/UseRestfulActions
    workflow_run = current_repository.workflow_runs.find_by(id: params[:id])
    return head :not_found unless workflow_run

    # Verify user has write access to Actions (consistent with API workflow_runs controller)
    unless current_repository.writable_by?(current_user)
      return render json: {
        error: "You do not have permission to cancel workflow runs in this repository."
      }, status: :forbidden
    end

    check_suite = workflow_run.check_suite
    return head :not_found unless check_suite

    check_suite.force_set_cancellation_state(actor: current_user)
    render json: {
      message: "Deployment cancelled successfully",
      status: "cancelled"
    }
  end

  def workflow_run_status # rubocop:todo GitHub/UseRestfulActions
    workflow_run = current_repository.workflow_runs.find_by(id: params[:id])
    return head :not_found unless workflow_run

    check_suite = workflow_run.check_suite
    return render json: { jobs: [], deployed_url: nil } unless check_suite

    # Use latest_check_runs to get the most recent run for each job name
    check_runs = check_suite.latest_check_runs

    deployed_url = T.let(nil, T.nilable(String))
    jobs = check_runs.map do |check_run|
      # Check if this job has a deployment with an environment URL
      if check_run.deployment && check_run.status == "completed"
        deployed_url = check_run.deployment.latest_status&.environment_url
      end

      {
        id: check_run.id,
        status: check_run.status,
        conclusion: check_run.conclusion,
      }
    end

    render json: { jobs: jobs, deployed_url: deployed_url }
  end

  private

  class DeployFormPayload < ReactPayload::Base
    def route_id
      "deployFormRoute"
    end

    def initialize(workflow_file_path:, commit_info:, branch:, framework:, package_manager:)
      @workflow_file_path = workflow_file_path
      @web_commit_info = commit_info
      @branch = branch
      @framework = framework
      @package_manager = package_manager
    end

    def payload
      {
        workflowFilePath: @workflow_file_path,
        webCommitInfo: @web_commit_info,
        branch: @branch,
        framework: @framework,
        packageManager: @package_manager
      }
    end
  end

  def resource_for_conditional_access
    current_repository
  end

  def target_for_conditional_access
    current_user
  end

  def require_feature_flags
    render_404 unless current_user&.feature_flag_enabled?(:pages_deploy_flow, default: false)
  end
end
