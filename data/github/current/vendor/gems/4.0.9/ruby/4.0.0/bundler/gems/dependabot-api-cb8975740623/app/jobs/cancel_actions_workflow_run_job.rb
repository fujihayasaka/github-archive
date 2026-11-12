# frozen_string_literal: true

class CancelActionsWorkflowRunJob < ApplicationJob
  queue_as :default
  default_retries_for_idempotent_jobs

  RETRYABLE_ERRORS = [
    *GitHubHelpers::RETRYABLE_ERRORS,
    Octokit::Unauthorized,
  ].freeze

  T.unsafe(self).include ActiveJob::Retry.new(
    strategy: RateLimitBackoffStrategy.new(
      limit: 10,
      retryable_exceptions: RETRYABLE_ERRORS,
    ),
    callback: proc do |exception, _|
      next unless exception.is_a?(Octokit::Unauthorized)

      update_job = arguments[0]
      uncache_installation_client(repo: update_job&.repo)
    end,
  )

  def perform(update_job, workflow_run_id)
    CancelActionsWorkflowRun.new(update_job:, workflow_run_id:).run
  end

  private

  def uncache_installation_client(repo:)
    return unless repo&.account&.current_installation_id

    GitHubHelpers.delete_cached_access_token_for(
      account: repo.account,
    )
  end
end
