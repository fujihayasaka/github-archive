# frozen_string_literal: true

# Processes failure outcomes returned from the Dependabot Updater in the form
# of UpdateJobErrors associated on with the provided UpdateJob
#
# This class should not be invoked to handle UpdateJob failures elswhere as this
# class implements retry strategies coupled to the Updater's behaviour.
#
# See: https://github.com/dependabot/dependabot-updater
class HandleUpdaterFailure
  attr_reader :update_job

  def self.retry(update_job)
    new(update_job: update_job).run
  end

  def initialize(update_job:)
    @update_job = update_job
  end

  def run
    handle_update_not_possible

    update_job.transition_to!(
      :processed_with_errors,
      errors: update_job.unique_errors.map(&:error_hash),
    )

    is_retriable = if retry_strategy&.retriable?
                     retry_strategy.retry!
                   else
                     NotifyGitHubOfFailureJob.send_errors_for(update_job)
                     cancel_stale_pull_request_update_if_required

                     false
                   end

    update_job.increment_metric("updater_failure.handled")

    is_retriable
  end

  private

  # For jobs that have no errors, nor any potential
  # pull requests, we should inject an error so that:
  # - the job transitions to processed_with_errors
  # - GitHub is notified the job has failed
  def handle_update_not_possible
    return unless update_job.unique_errors.none?

    update_job.
      update_job_errors.
      create!(error_type: "update_not_possible")
  end

  def retry_strategy
    if error_present?("octokit_rate_limited")
      RateLimitedRetryStrategy.new(update_job)
    elsif error_present?("octokit_unauthorized")
      DefaultRetryStrategy.new(update_job)
    end
  end

  def error_present?(error_type)
    update_job.unique_errors.any? { |e| e.error_type == error_type }
  end

  def cancel_stale_pull_request_update_if_required
    return unless update_job.pull_request_transition&.most_recent?

    CancelStalePullRequestUpdate.
      set(wait: 10.minutes).
      perform_later(update_job: update_job)
  end
end
