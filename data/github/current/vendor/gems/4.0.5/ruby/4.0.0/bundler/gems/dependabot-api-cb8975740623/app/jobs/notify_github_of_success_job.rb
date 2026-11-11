# frozen_string_literal: true

class NotifyGitHubOfSuccessJob < ApplicationJob
  queue_as :create_pull_request_p2
  default_retries_for_idempotent_jobs

  T.unsafe(self).include ActiveJob::Retry.new(
    strategy: :exponential,
    limit: 5,
    retryable_exceptions: [
      MarkGitHubJobComplete::MissingSubjectError, # PullRequest not there yet.
      GitHubGraphQL::ServerError,
    ],
  )

  def perform(update_job:, pull_request:)
    MarkGitHubJobComplete.new(update_job: update_job,
                              pull_request: pull_request).run
  # Raised when the repo is no longer accessible to the installation
  rescue GitHubGraphQL::UnauthorizedError
    true
  end
end
