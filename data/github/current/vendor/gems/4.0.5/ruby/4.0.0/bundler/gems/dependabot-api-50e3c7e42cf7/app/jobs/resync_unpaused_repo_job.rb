# frozen_string_literal: true

class ResyncUnpausedRepoJob < ApplicationJob
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

  def perform(repo:)
    sync_result = SynchronizeRepoState.new(repo: repo, event_source: "repo.unpaused").run

    return unless sync_result.success?

    CheckRepoHasCiJob.perform_later(repo: repo)
  end

  private

  def uncache_installation_client
    @installation_github_client = nil

    GitHubHelpers.delete_cached_access_token_for(
      account: repo.account,
    )
  end
end
