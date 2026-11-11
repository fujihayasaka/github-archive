# frozen_string_literal: true

# Attempts to cancel an actions workflow job as a reusable action.
class CancelActionsWorkflowRun
  def initialize(update_job:, workflow_run_id:)
    @update_job = update_job
    @repo = @update_job&.repo
    @workflow_run_id = workflow_run_id
  end

  def run
    return false unless cancelable?

    Dependabot::Logger.log_context(log_context("run")) do
      cancel_workflow_run.tap do |result|
        if result
          @update_job.increment_metric("cancel_actions_workflow_run.completed", tags: { result: "success" })
        else
          @update_job.increment_metric("cancel_actions_workflow_run.completed", tags: { result: "failure" })
        end
      end
    end
  end

  private

  def cancelable?
    return false unless @update_job.present? && @update_job.actions?
    return false if @repo.blank?

    @workflow_run_id&.positive?
  end

  def cancel_workflow_run # rubocop:disable Metrics/MethodLength
    result = installation_github_client.cancel_workflow_run(@repo.github_id, @workflow_run_id)
    if installation_github_client.last_response&.status&.>= 400
      # This specific Octokit API call checks the response code
      # against a known set of "good" codes and returns true/false.
      # Why?
      # Check for a failure status code and raise the appropriate octokit
      # error so we can handle it.
      raise Octokit::Error.from_response(installation_github_client.last_response)
    end

    result
  rescue *SynchronizeRepoState::HANDLED_ERRORS => e
    # Log and handle errors that result in synchronizing repo state
    log_failure("Synchronizing Repo: #{e.message}")
    SynchronizeRepoState.new(repo: @repo, event_source: "action.cancel_actions_workflow_run").run

    false
  rescue Octokit::Conflict => e
    # Conflict is returned when the workflow run not
    # in a cancelable state, e.g. it's already completed
    log_failure(e.message)
    false
  rescue Octokit::InternalServerError => e
    # InternalServerError with this message is returned
    # when the workflow run can be canceled, but failed
    if e.message.include?("Failed to cancel workflow run")
      log_failure(e.message)
      return false
    end

    # Unexpected internal server error, log and re-raise
    log_error(e)
    raise
  rescue Octokit::Error => e
    # Log and re-raise all other Octokit errors
    log_error(e)
    raise
  end

  def log_failure(cause = nil)
    Dependabot::Logger.info(
      msg: "Canceling actions workflow run was not successful",
      result: "failure",
      failure_cause: cause || "unknown",
    )
  end

  def log_error(err)
    @update_job.increment_metric("cancel_actions_workflow_run.completed", tags: { result: "error" })

    Dependabot::Logger.error(
      msg: "Canceling actions workflow run was not successful",
      result: "error",
      "exception.message": err.message,
      "exception.type": err.class.name,
    )
  end

  def log_context(function)
    {
      "code.namespace": self.class.name,
      "code.function": function,
      "gh.actions.workflow_run.id": @workflow_run_id,
    }.merge(@update_job.telemetry_attributes)
  end

  def installation_github_client
    @installation_github_client ||=
      GitHubHelpers::ClientWithRetries.
      new(account: @repo.account)
  end
end
