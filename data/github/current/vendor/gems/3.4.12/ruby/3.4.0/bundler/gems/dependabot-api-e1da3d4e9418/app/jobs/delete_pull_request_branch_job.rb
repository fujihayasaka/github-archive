# frozen_string_literal: true

# Wrapper for deleting a pull request on GitHub. Doing this in a job allows us
# to retry any exceptions from GitHub (server errors or connection failures).
class DeletePullRequestBranchJob < ApplicationJob
  queue_as :default
  default_retries_for_idempotent_jobs

  # Retry over the next 2.5 hours, with exponential backoff
  T.unsafe(self).include ActiveJob::Retry.new(
    strategy: RateLimitBackoffStrategy.new(
      limit: 10,
      retryable_exceptions:
        [*GitHubHelpers::RETRYABLE_ERRORS, Octokit::Unauthorized],
    ),
  )

  def perform(pull_request:)
    DeletePullRequestBranch.new(pull_request: pull_request).run
  end
end
