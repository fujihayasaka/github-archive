# frozen_string_literal: true

class GitHubActionComputeUsageHandler
  # GitHub cloud alone uses this hydro event.
  # TODO Replace the WorkflowRun (handleWebhook) with this hydro event once
  # the ComputeUsage hydro event is published in GHES.
  GITHUB_DEPENDABOT_USER_ID = Dependabot::Application.github_dependabot_user_id

  def self.run(message)
    new(message.value).run
  end

  def initialize(payload)
    @payload = payload
  end

  def run
    return unless dependabot_update_action?

    log_compute_usage_event
    return unless workflow_has_failed?

    HandleFailedActionRunJob.perform_later(workflow_run_id: workflow_run_id,
                                           workflow_job_conclusion: check_run_conclusion)
  end

  private

  attr_reader :payload

  # This guards against us reacting to any out of band retries via Actions APIs we haven't locked down
  def dependabot_update_action?
    invoking_user_id == GITHUB_DEPENDABOT_USER_ID &&
      invoking_event_type == "dynamic"
  end

  def log_compute_usage_event
    Dependabot::Logger.info(
      msg: "Dependabot ComputeUsage hydro event received",
      "code.namespace": "GitHubActionComputeUsageHandler",
      "gh.actions.workflow_run.id": workflow_run_id,
      "gh.repo.id": github_repo_id,
      "gh.check_run.conclusion": check_run_conclusion
    )
  end

  def workflow_has_failed?
    check_run_conclusion != :RESULT_SUCCESS
  end

  def invoking_user_id
    payload[:invoking_user_id]
  end

  def github_repo_id
    payload[:repository_id]
  end

  def workflow_run_id
    payload[:workflow_run_id]
  end

  def check_run_conclusion
    payload[:check_run_conclusion]
  end

  def invoking_event_type
    payload[:invoking_event_type]
  end
end
