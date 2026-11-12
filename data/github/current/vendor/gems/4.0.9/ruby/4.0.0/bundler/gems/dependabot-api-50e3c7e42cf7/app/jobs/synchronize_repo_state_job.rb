# frozen_string_literal: true

require "github_helpers"

class SynchronizeRepoStateJob < ApplicationJob
  queue_as :default
  default_retries_for_idempotent_jobs

  # Retry over the next 2.5 hours, with exponential backoff
  T.unsafe(self).include ActiveJob::Retry.new(
    strategy: RateLimitBackoffStrategy.new(
      limit: 10,
      retryable_exceptions: [
        *GitHubHelpers::RETRYABLE_ERRORS,
        Octokit::Unauthorized,
      ],
    ),
    callback: proc do |e, _|
      next unless e.is_a?(Octokit::Unauthorized)

      uncache_installation_client
    end,
  )

  def perform(repo:, event_source: nil)
    @repo = repo
    synchronize_result = SynchronizeRepoState.new(repo: repo, event_source: event_source).run
    log_job_state(synchronize_result)

    synchronize_result
  end

  private

  attr_reader :repo

  def uncache_installation_client
    @installation_github_client = nil

    GitHubHelpers.delete_cached_access_token_for(
      account: repo.account,
    )
  end

  def log_job_state(synchronize_result)
    if synchronize_result.success?
      # Log success if the operation was successful
      Dependabot::Logger.info(
        msg: "SynchronizeRepoStateJob completed successfully",
        "code.namespace": "SynchronizeRepoStateJob",
        "gh.repo.id": repo.github_id,
      )
    else
      # Log error if the operation encountered an error
      Dependabot::Logger.error(
        msg: "SynchronizeRepoStateJob encountered an error",
        "code.namespace": "SynchronizeRepoStateJob",
        reason: synchronize_result.reason,
        "gh.repo.id": repo.github_id,
      )
    end
  end
end
