# frozen_string_literal: true

# Wrapper for creating an issue on GitHub. Doing this in a job allows us to
# retry any exceptions from GitHub (server errors or connection failures).
class NotifyGitHubOfFailureJob < ApplicationJob
  queue_as :default
  default_retries_for_idempotent_jobs

  class IntermittentFailure < StandardError; end

  # Retry over the next 2.5 hours, with exponential backoff
  T.unsafe(self).include ActiveJob::Retry.new(
    strategy: RateLimitBackoffStrategy.new(
      limit: 10,
      retryable_exceptions: [
        *GitHubHelpers::RETRYABLE_ERRORS,
        GitHubGraphQL::ServerError,
        IntermittentFailure,
        MarkGitHubJobErrored::GraphQLQueryError,
      ],
    ),
  )

  def self.send_errors_for(update_job)
    return unless update_job.dotcom_request?
    return if update_job.unique_errors.empty?

    # TODO: In cases where we have multiple errors, we should roll them up into a single response
    #       currently, the last error wins.
    #
    #       This is tolerated as we generally only have 1 error for Security Updates as they focus
    #       a single dependency to update, but it can create confusion when debugging complex failures.
    #
    #       Historically, this has never been addressed as we plan to have the GitHub UI poll the errors
    #       from Dependabot API, negating the need to relay anything other than the status of the job.
    update_job.unique_errors.each do |error|
      perform_later(
        update_job: update_job,
        error_hash: error.error_hash,
      )
    end
  end

  def perform(error_hash:, update_job:)
    error_type = error_hash.fetch("error-type")

    case error_type
    when *UpdateJobError::ALLOWED_UPDATE_JOB_ERROR_TYPES
      MarkGitHubJobErrored.new(
        update_job: update_job,
        error_hash: error_hash,
      ).run
    else raise "Unknown issue type: #{error_type}"
    end
  rescue MarkGitHubJobErrored::GitHubAppError
    resync = SynchronizeRepoState.new(
      repo: update_job.repo,
      event_source: "notify_github_of_failure_job"
    ).run

    # raise an error to force a retry if the repo was successfully synchronized
    raise IntermittentFailure if resync.success?

    false
  rescue MarkGitHubJobErrored::StateError
    true
  # Raised when the repo is no longer accessible to the installation
  rescue GitHubGraphQL::UnauthorizedError
    true
  end
end
