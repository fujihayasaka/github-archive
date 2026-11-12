# frozen_string_literal: true

# Wrapper for creating a missing Dependabot PR comment on GitHub. Doing this in a job
# allows us to retry any exceptions from GitHub (server errors or connection
# failures).
class CreateMissingDependabotPrCommentJob < ApplicationJob
  queue_as :default
  default_retries_for_idempotent_jobs

  # Retry over the next ~20 minutes, with exponential backoff
  T.unsafe(self).include ActiveJob::Retry.new(
    strategy: RateLimitBackoffStrategy.new(
      limit: 6,
      retryable_exceptions: GitHubHelpers::RETRYABLE_ERRORS,
    ),
  )

  def perform(repo:, github_number:, comment_url:, pr_closed_at:, pr_created_at:)
    CreateMissingDependabotPrComment.new(
      repo: repo, github_number: github_number, comment_url: comment_url,
      pr_closed_at: pr_closed_at, pr_created_at: pr_created_at
    ).run
  end
end
