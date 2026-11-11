# frozen_string_literal: true

# Gets an UpdateJob's status from the actions api
#

class UpdateJobActionsStatusJob < ApplicationJob
  queue_as :default
  default_retries_for_idempotent_jobs

  T.unsafe(self).include ActiveJob::Retry.new(
    strategy: RateLimitBackoffStrategy.new(
      limit: 3,
      retryable_exceptions: [
        *GitHubHelpers::RETRYABLE_ERRORS,
      ],
    ),
    callback: proc do |exception, _|
      next unless exception.is_a?(Octokit::Unauthorized)
    end,
  )

  def perform(update_job_id:) # rubocop:disable Metrics/MethodLength
    @update_job = UpdateJob.find(update_job_id)
    return if @update_job.completed?

    Dependabot::Exceptions.push(
      "gh.dependabot_api.update_job.id": update_job_id,
    )

    begin
      actions_run = installation_github_client.workflow_run(
        @update_job.update_config.repo.github_id,
        @update_job.actions_workflow_run_id
      )
    rescue Octokit::NotFound => e
      raise unless @update_job.repo.config_feature_enabled?(:workflow_actions_404_handler)

      HandleActionsRunnerFailure.new(update_job: @update_job, error: e).run
      return
    end
    return unless actions_run.status == GitHub::CheckRun::Status::COMPLETED &&
                  actions_run.conclusion != GitHub::CheckRun::Conclusion::SUCCESS

    @update_job.increment_metric(
      "actions.early_failure",
      tags: { conclusion: actions_run.conclusion },
    )

    Dependabot::Logger.info(
      msg: "Dependabot ComputeUsage hydro event received",
      "code.namespace": "UpdateJobActionsStatusJob",
      "gh.actions.workflow_run.id": @update_job.actions_workflow_run_id,
      "gh.repo.id": @update_job.update_config.repo.github_id,
      "gh.check_run.conclusion": actions_run.conclusion
    )

    HandleFailedActionRunJob.perform_now(
      workflow_run_id: @update_job.actions_workflow_run_id,
      workflow_job_conclusion: actions_run.conclusion,
    )
  end

  def installation_github_client
    @installation_github_client ||=
      GitHubHelpers::ClientWithRetries.
      new(account: @update_job.update_config.repo.account)
  end
end
