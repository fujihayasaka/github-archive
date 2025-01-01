# typed: true
# frozen_string_literal: true

require "github-launch"

class CheckSuitesController < AbstractRepositoryController
  before_action :require_push_access, except: [:show_partial, :download_logs, :download_artifact]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    only: [:download_artifact]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    only: [:download_logs]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Configurations,
    only: [:show_partial]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:download_logs, :show_partial], optional: true

  def rerequest # rubocop:todo GitHub/UseRestfulActions
    check_suite = find_check_suite
    return render_404 unless check_suite

    if check_suite.rerequestable
      # We only want to allow re-requestable check suites for XHR requests.
      begin
        if check_suite.actions_app?
          # If the check_suite is for actions, only_failed_check_suites is false since re-running individual jobs is not currently supported
          check_suite.rerequest(actor: current_user, only_failed_check_runs: params[:only_failed_check_runs] == "true", only_failed_check_suites: false)
        else
          check_suite.rerequest(
            actor: current_user,
            only_failed_check_runs: params[:only_failed_check_runs] == "true",
            only_failed_check_suites: params[:only_failed_check_suites] != nil ? params[:only_failed_check_suites] == "true" : true
          )
        end
      rescue CheckSuite::ActionsDependency::ExpiredWorkflowRunError
        head :bad_request and return if request.xhr?

        flash[:error] = "Unable to re-run this workflow because it was created over a month ago."
        redirect_to :back and return
      rescue CheckSuite::AlreadyRerunningError
        # If the check suite is already re-running, we want to return a Bad
        # Request.
        head :bad_request and return if request.xhr?

        flash[:error] = "This check suite is already re-running."
        redirect_to :back and return
      rescue CheckSuite::MissingWorkflowRunError
        head :bad_request and return if request.xhr?

        flash[:error] = "Unable to re-run workflow because no workflow run was found."
        redirect_to :back and return
      rescue CheckSuite::DisabledWorkflowError
        head :bad_request and return if request.xhr?

        flash[:error] = "Unable to re-run disabled workflow."
        redirect_to :back and return
      rescue CheckSuite::ExpiredLogsError
        head :bad_request and return if request.xhr?

        flash[:error] = "Unable to re-run check suite with expired logs."
        redirect_to :back and return
      rescue CheckSuite::NotRerequestableError
        head :bad_request and return if request.xhr?

        flash[:error] = "Unable to re-run check suite."
        redirect_to :back and return
      end


      head :ok and return if request.xhr?

      checks_name = check_suite.actions_app? ? "jobs" : "checks"
      message = if check_suite.actions_app?
        "You have successfully requested a re-run of the workflow run."
      else
        "You have successfully requested checks from #{check_suite.github_app.name}."
      end
      flash[:notice] = message
      redirect_to :back
    else
      head :bad_request and return if request.xhr?

      flash[:error] = "Re-runs for this check suite are disabled."
      redirect_to :back and return
    end

  end

  def show_partial # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless request.xhr?

    check_suite = find_check_suite
    return render_404 unless check_suite

    selected_check_run = check_suite.check_runs.find_by_id(params[:selected_check_run_id].to_i)
    pull = current_repository.pull_requests.find_by_id(params[:pull_id].to_i)
    check_suite_selected = params[:check_suite_selected] == "true"
    check_suite_focus = params[:check_suite_focus] == "true"

    respond_to do |format|
      format.html do
        render Checks::SidebarItemComponent.new(
          check_suite: check_suite,
          selected_check_run: selected_check_run,
          check_suite_selected: check_suite_selected,
          check_suite_focus: check_suite_focus,
          pull: pull,
          current_repository: current_repository,
          repo_writable: current_user_can_push?,
        ), layout: false
      end
    end
  end

  def cancel # rubocop:todo GitHub/UseRestfulActions
    check_suite = find_check_suite
    return render_404 unless check_suite

    unless check_suite.actions_app?
      flash[:error] = "Cancelling check suites is not enabled for this GitHub app."
      redirect_to :back and return
    end

    return render_404 unless GitHub.actions_enabled?

    if check_suite.completed?
      flash[:error] = "Cannot cancel a check suite that is completed."
      redirect_to :back and return
    end

    result = check_suite.cancel(actor: current_user)

    if result.call_succeeded?
      flash[:notice] = "You have successfully requested the workflow to be canceled."
    else
      flash[:error] = "Failed to cancel workflow."
    end

    redirect_to :back
  end

  def download_artifact # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless logged_in?

    check_suite = find_check_suite
    return render_404 unless check_suite

    artifact = check_suite.artifacts.find(params[:artifact_id])
    return render_404 unless artifact

    if artifact.is_results_artifact?
      return render_404 unless artifact.source_url

      results_ids = artifact.get_results_ids_from_source_url
      return render_404 unless results_ids
      key = "actions.actions_results_artifact_request"

      result = ActionsResults::Twirp.artifact_client.get_download_url_for_artifact(
        workflow_job_run_backend_id: results_ids[:workflow_job_run_backend_id],
        workflow_run_backend_id: results_ids[:workflow_run_backend_id],
        name: artifact.name,
      )

      if result.call_succeeded? && result.value&.url
        GitHub.dogstats.increment("#{key}.succeeded", tags: ["artifacts:true"])
        redirect_to result.value&.url, status: 307
      else
        GitHub.dogstats.increment("#{key}.failed", tags: ["artifacts:true"])
        flash[:error] = "Failed to generate URL to download artifact."
        redirect_back fallback_location: checks_path(ref: check_suite.head_sha)
      end
    else
      is_fallback = false
      if !GitHub.enterprise? && check_suite.external_id && artifact.expires_after_cutoff_date? && current_repository.feature_enabled?(:actions_check_results_for_migrated_artifact)
        key = "actions.actions_results_migrated_artifact_request"

        result = ActionsResults::Twirp.artifact_client.get_download_url_for_artifact(
          workflow_run_backend_id: check_suite.external_id,
          workflow_job_run_backend_id: Artifact::MIGRATED_ARTIFACT_EMPTY_JOB_ID, # v3 Artifacts are run-scoped, so we'll use an empty GUID here
          name: artifact.name
        )
        if result.call_succeeded? && result.value&.url
          GitHub.dogstats.increment("#{key}.succeeded", tags: ["artifacts:true"])
          redirect_to result.value&.url, status: 307
          return
        else
          GitHub.dogstats.increment("#{key}.failed", tags: ["artifacts:true"])
          is_fallback = true
        end
      end

      key = "actions.exchange_url_request"
      if is_fallback
        key = "#{key}.fallback"
      end
      result = Launch::Twirp.artifacts_exchange_client_for_check_suite(check_suite).exchange_url_for(
        unauthenticated_url: artifact.source_url,
        repository: current_repository,
        resource_type: Launch::Twirp::ResourceType::DOWNLOAD_ARTIFACT
      )
      if result.call_succeeded?
        GitHub.dogstats.increment("#{key}.succeeded", tags: ["artifacts:true"])
        redirect_to result.value.authenticated_url, status: 307
      else
        GitHub.dogstats.increment("#{key}.failed", tags: ["artifacts:true"])
        flash[:error] = "Failed to generate URL to download artifact."
        redirect_back fallback_location: checks_path(ref: check_suite.head_sha)
      end
    end
  end

  def delete_artifact # rubocop:todo GitHub/UseRestfulActions
    check_suite = find_check_suite
    return render_404 unless check_suite

    artifact = check_suite.artifacts.find(params[:artifact_id])
    return render_404 unless artifact

    begin
      artifact.destroy
      flash[:notice] = "The artifact was successfully deleted."
    rescue RuntimeError
      flash[:error] = "Failed to delete the artifact."
    end

    redirect_back fallback_location: checks_path(ref: check_suite.head_sha)
  end

  def download_logs # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless logged_in?

    check_suite = find_check_suite
    return render_404 unless check_suite

    if check_suite.expired_logs?
      flash[:error] = "The logs for this run have expired and are no longer available. Logs may have been removed based on retention settings on the repo at the time the run was started."
      redirect_back fallback_location: checks_path(ref: check_suite.head_sha) and return
    end

    attempt = params[:attempt]
    if attempt.present?
      workflow_run_execution = check_suite.workflow_run&.workflow_run_executions&.find_by(attempt: attempt)
      attempt_log_url = workflow_run_execution&.completed_log_url
      return render_404 unless attempt_log_url
    end

    log_url = attempt_log_url || check_suite.completed_log_url
    return render_404 unless log_url

    redirect_url = download_logs_archive_url_from_backend(log_url, check_suite, workflow_run_execution&.external_id || check_suite&.external_id)

    if redirect_url.nil?
      flash[:error] = "Failed to generate URL to download logs. Logs may have been removed based on retention settings on the repo at the time the run was started."
      redirect_back fallback_location: checks_path(ref: check_suite.head_sha)
    else
      redirect_to redirect_url, status: 307
    end
  end

  private

  def download_logs_archive_url_from_backend(log_url, check_suite, workflow_run_backend_id)
    if check_suite.workflow_run.logs_via_results_service?
      return nil if workflow_run_backend_id.nil?

      result = ActionsResults::Twirp.log_client.get_completed_run_log_archive(workflow_run_backend_id: workflow_run_backend_id)
      redirect_url = if result.call_succeeded?
        result.value.log_url
      else
        nil
      end
    else
      request = GitHub::Launch::Services::Artifactsexchange::ExchangeURLRequest.new({
        unauthenticated_url: log_url,
        repository_id: GitHub::Launch::Pbtypes::GitHub::Identity.new(global_id: get_global_id(current_repository)),
        resource_type: GitHub::Launch::Services::Artifactsexchange::ResourceType::TYPE_COMPLETED_RUN_LOG,
      })

      result = Launch::Twirp.artifacts_exchange_client_for_check_suite(check_suite).exchange_url(request)

      if result.call_succeeded?
        redirect_url = result.value.authenticated_url
      else
        redirect_url = nil
      end
    end

    redirect_url
  end

  def require_push_access
    render_404 unless current_user_can_push?
  end

  def find_check_suite
    check_suite = CheckSuite.where(id: params[:id]).first
    if !check_suite || check_suite.repository_id != current_repository.id
      return nil
    end
    check_suite
  end

  def get_global_id(entity)
    use_next_gid = !GitHub.enterprise?
    use_next_gid ? entity.next_global_id : entity.global_relay_id
  end
end
