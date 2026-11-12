# frozen_string_literal: true

# Wrapper for creating a CI failure comment on a merge-candidate PR. Doing this
# in a job allows us to retry any exceptions from GitHub (server errors or
# connection failures).
class CreateCheckOrStatusFailureCommentJob < ApplicationJob
  queue_as :default
  default_retries_for_idempotent_jobs

  # Retry over the next 2.5 hours, with exponential backoff
  T.unsafe(self).include ActiveJob::Retry.new(
    strategy: RateLimitBackoffStrategy.new(
      limit: 10,
      retryable_exceptions: [
        *GitHubHelpers::RETRYABLE_ERRORS,
        GitHub::Twirp::DependabotPullRequests::TransientServiceError,
        GitHub::Twirp::DependabotPullRequests::TransientTwirpError,
      ],
    ),
  )

  def perform(pull_request:)
    CreateCheckOrStatusFailureComment.new(pull_request: pull_request).run
  end
end
