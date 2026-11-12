# frozen_string_literal: true

class HandleFailedActionRunJob < ApplicationJob
  queue_as :default
  default_retries_for_idempotent_jobs

  T.unsafe(self).include ActiveJob::Retry.new(
    strategy: RateLimitBackoffStrategy.new(
      limit: 10,
      retryable_exceptions:
        [*GitHubHelpers::RETRYABLE_ERRORS, Octokit::Unauthorized],
    ),
  )

  # rubocop:disable Lint/UnusedMethodArgument
  def perform(workflow_run_id:, workflow_job_conclusion: nil, github_repo_id: nil)
    update_job = UpdateJob.find_by!(actions_workflow_run_id: workflow_run_id)

    return if job_already_processed?(update_job)

    mark_as_processed_with_errors(update_job: update_job, workflow_job_conclusion: workflow_job_conclusion)
  rescue ActiveRecord::RecordNotFound => e
    Dependabot::Logger.error(
      msg: "Could not find UpdateJob for workflow_run_id",
      "workflow_run_id": workflow_run_id,
      error: e.message
    )
  end
  # rubocop:enable Lint/UnusedMethodArgument

  private

  # This method checks the job is not currently in the `processing` or `enqueued` state. If this is
  # the case there are three possibilities:
  #
  # - It has been marked as `processed_with_errors` by the action itself, which will have provided better fidelity
  #   errors from dependabot-core or the action itself.
  # - It has been marked as `processed` and the workflow run failed on a cleanup or actions-internal step, in which case
  #   Dependabot is actually in a happy state despite the run turning red overall.
  # - The job has moved into another terminal state such as `timed_out`, `cancelled` or `abandoned` by a separate
  #   process.
  #
  # In any of these cases, pushing an additional error unto the object isn't terribly useful as Dependabot will have
  # already shown an outcome to the end user and the action will remain as a trace of the failure.
  def job_already_processed?(update_job)
    !update_job.in_state?(:processing, :enqueued)
  end

  # Adds an UpdateJobError and transitions the UpdateJob to `processed_with_errors`.
  def mark_as_processed_with_errors(update_job:, workflow_job_conclusion: nil)
    if workflow_job_conclusion == :RESULT_CANCELLED
      HandleUpdaterTimeout.new(update_job: update_job, event_source: "hydro.github_actions_v0_compute_usage").run
    else
      HandleActionsRunnerFailure.new(update_job: update_job).run
    end
  end
end
