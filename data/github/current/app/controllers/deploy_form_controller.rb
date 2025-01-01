# typed: true
# frozen_string_literal: true

class DeployFormController < AbstractRepositoryController
  include WebCommitControllerMethods

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
    only: [:show, :index]

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
