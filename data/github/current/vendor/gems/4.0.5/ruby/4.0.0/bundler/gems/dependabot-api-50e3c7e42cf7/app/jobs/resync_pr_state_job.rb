# frozen_string_literal: true

require "github_helpers"

# Wrapper for resyncing a PRs state with GitHub. Doing this in a job allows us
# to retry any exceptions from GitHub (server errors or connection failures).
class ResyncPrStateJob < ApplicationJob
  queue_as :default
  default_retries_for_idempotent_jobs

  # Retry over the next 2.5 hours, with exponential backoff
  T.unsafe(self).include ActiveJob::Retry.new(
    strategy: RateLimitBackoffStrategy.new(
      limit: 10,
      retryable_exceptions:
        [*GitHubHelpers::RETRYABLE_ERRORS, Octokit::Unauthorized],
    ),
    callback: proc do |exception, _|
      next unless exception.is_a?(Octokit::Unauthorized)

      uncache_installation_client
    end,
  )

  def perform(pull_request:)
    @pull_request = pull_request
    return unless pull_request.repo.account.active?

    Statesman::Machine.retry_conflicts(3) do
      return if pull_request.current_state == github_state

      pull_request.transition_to!(github_state)
    end
  rescue *SynchronizeRepoState::HANDLED_ERRORS
    SynchronizeRepoState.new(
      repo: pull_request.repo,
      event_source: "job.resync_pr_state",
    ).run
  end

  private

  attr_reader :pull_request

  def github_state
    if github_pr.merged then "merged"
    elsif github_pr.state == "closed" then "closed"
    else
      "up_to_date"
    end
  end

  def github_pr
    @github_pr ||= installation_github_client.pull_request(
      pull_request.repo.github_id,
      pull_request.github_number,
    )
  end

  def installation_github_client
    @installation_github_client ||=
      GitHubHelpers::ClientWithRetries.new(
        account: pull_request.repo.account,
      )
  end

  def uncache_installation_client
    GitHubHelpers.delete_cached_access_token_for(
      account: pull_request.repo.account,
    )
    @installation_github_client = nil
  end
end
