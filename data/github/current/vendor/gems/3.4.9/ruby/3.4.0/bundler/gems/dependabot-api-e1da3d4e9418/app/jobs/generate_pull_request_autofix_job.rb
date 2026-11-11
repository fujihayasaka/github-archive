# frozen_string_literal: true

# Generates an autofix comment for a Dependabot update
class GeneratePullRequestAutofixJob < ApplicationJob
  queue_as :default
  default_retries_for_idempotent_jobs

  # Retry over the next 2.5 hours, with exponential backoff
  T.unsafe(self).include ActiveJob::Retry.new(
    strategy: RateLimitBackoffStrategy.new(
      limit: 10,
      retryable_exceptions: [
        *GitHubHelpers::RETRYABLE_ERRORS,
        *GeneratePullRequestAutofix::FETCH_JOB_LOG_RETRY_ERRORS,
      ],
    ),
  )

  rescue_from StandardError do |exception|
    autofix_job = arguments[0][:autofix_job]
    autofix_job.complete_github_check_run(conclusion: GitHub::CheckRun::Conclusion::FAILURE)

    # If fetching job logs does not ever succeed, it is outside
    # this jobs control and should not be logged as an error.
    # TODO: when state tracking is added to AutofixSuggestionJob,
    # update the job's state to error.
    raise unless GeneratePullRequestAutofix::FETCH_JOB_LOG_RETRY_ERRORS.include?(exception.class)
  end

  def perform(autofix_job:)
    Dependabot::Exceptions.push(autofix_job.telemetry_attributes)

    GeneratePullRequestAutofix.new(autofix_job: autofix_job).run
  end
end
