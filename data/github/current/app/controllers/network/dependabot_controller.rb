# typed: true
# frozen_string_literal: true

class Network::DependabotController < GitContentController

  skip_before_action :try_to_expand_path
  before_action :ensure_dependabot_available
  before_action :ensure_repo_adminable, only: [:enable]

  layout "repository"

  stylesheet_bundle :insights

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::SecurityProductsEnablement,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Spokes,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Permissions,
    ApplicationRecord::Iam,
    ApplicationRecord::Memex,
    ApplicationRecord::Billing,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::SecurityProductsEnablement,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Spokes,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Iam,
    ApplicationRecord::Memex,
    ApplicationRecord::Billing,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :show],
    optional: true

  def index
    config_file, update_configs, dependabot_unavailable, dependabot_error = nil
    config_file_enabled = config_file_enabled?

    # If the config file is enabled, retrieve information from the Dependabot Service
    if config_file_enabled && dependabot_installed?
      begin
        response = Dependabot::Twirp.update_configs_client.list_update_configs(
          repository_id: current_repository.id,
          owner_id: current_repository.owner_id,
          config_file_exists: current_repository.dependabot_config_file_exists?,
        )
        config_file = response.config_file
        update_configs = response.update_configs
      rescue Dependabot::Twirp::ServiceUnavailableError
        dependabot_unavailable = true
      rescue Dependabot::Twirp::Error => error
        dependabot_error = error
      end
    end

    respond_to do |format|
      format.html do
        render "network/dependabot/index", locals: {
          config_file: config_file,
          config_file_enabled: config_file_enabled,
          update_configs: update_configs || [],
          dependabot_unavailable: dependabot_unavailable,
          dependabot_error: dependabot_error,
        }
      end
    end
  end

  def show
    check_run, update_job, update_job_logs, dependabot_unavailable, dependabot_error = nil

    begin
      response = Dependabot::Twirp.update_jobs_client.get_job_logs(
        repository_id: current_repository.id,
        update_job_id: params[:update_job_id].to_i,
      )
      if response.update_job
        update_job = Dependabot::Twirp::UpdateJobStatusDecorator.new(response.update_job)
        if update_job.actions_workflow_run_id.nonzero?
          workflow_run = Actions::WorkflowRun.includes(:check_suite).find_by(
            id: update_job.actions_workflow_run_id,
            repository_id: current_repository.id,
          )
          check_suite = workflow_run&.check_suite
          check_run = if check_suite
            Checks.domain.check_runs.first_for_check_suite(check_suite)
          end
        elsif update_job.actions_external_id.present?
          check_suite = current_repository.actions_check_suites.find_by(external_id: update_job.actions_external_id)
          check_run = if check_suite
            Checks.domain.check_runs.first_for_check_suite(check_suite)
          end
        end
      end
      update_job_logs = response.update_job_logs
    rescue Dependabot::Twirp::ServiceUnavailableError
      dependabot_unavailable = true
    rescue Dependabot::Twirp::Error => error
      dependabot_error = error
    end

    respond_to do |format|
      format.html do
        render "network/dependabot/show", locals: {
          update_job: update_job,
          check_run: check_run,
          update_job_logs: update_job_logs,
          dependabot_unavailable: dependabot_unavailable,
          dependabot_error: dependabot_error,
        }
      end
    end
  end

  def create
    update_job, dependabot_unavailable, dependabot_error = nil

    begin
      response = Dependabot::Twirp.update_configs_client.trigger_update_job(
        repository_id: current_repository.id,
        update_config_id: params.fetch(:update_config_id).to_i
      )
      update_job = response.update_job
    rescue Dependabot::Twirp::ServiceUnavailableError
      dependabot_unavailable = true
    rescue Dependabot::Twirp::Error => error
      dependabot_error = error
    end

    respond_to do |format|
      format.html do
        if dependabot_error
          flash[:error] = dependabot_error.msg
        elsif dependabot_unavailable || update_job.nil?
          flash[:error] = "Failed to check for updated dependencies."
        else
          flash[:notice] = "Started checking for updated dependencies."
        end

        redirect_to action: :index
      end
    end
  end

  def enable # rubocop:todo GitHub/UseRestfulActions
    return redirect_to action: :index if dependabot_already_enabled?

    dependabot_installed = dependabot_installed? ? true : perform_dependabot_install&.success?

    if dependabot_installed
      # Avoid flipping the setting if the installation failed for some reason
      SecurityProduct::DependabotConfigFile.new(current_repository).enable(actor: current_user)
    end

    respond_to do |format|
      format.html do
        if dependabot_installed && config_file_enabled?
          flash[:notice] = "Dependabot was enabled."
        else
          flash[:error] = "Failed to enable Dependabot."
        end

        redirect_to action: :index
      end
    end
  end

  private

  def ensure_dependabot_available
    unless current_repository.automated_dependency_updates_visible_to?(current_user)
      render_404
    end
  end

  def ensure_repo_adminable
    render_404 unless current_repository.adminable_by?(current_user)
  end

  def dependabot_already_enabled?
    dependabot_installed? && config_file_enabled?
  end

  def dependabot_installed?
    current_repository.dependabot_installed?
  end

  def perform_dependabot_install
    AutomaticAppInstallation.trigger(
      type: :button_clicked,
      originator: GitHub.dependabot_github_app,
      actor: current_repository,
      async: false
    ).first
  end

  def config_file_enabled?
    SecurityProduct::DependabotConfigFile.new(current_repository).enabled?
  end
end
