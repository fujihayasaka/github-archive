# frozen_string_literal: true

require "github_helpers"

# Wrapper for updating a pull request's base branch. Doing this in a job allows
# us to retry any exceptions from GitHub (server errors or connection failures).
class UpdatePullRequestBaseBranchJob < ApplicationJob
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
    UpdatePullRequestBaseBranch.new(pull_request: pull_request).run
  end

  private

  attr_reader :pull_request

  def uncache_installation_client
    GitHubHelpers.delete_cached_access_token_for(
      account: pull_request.repo.account,
    )
  end
end
