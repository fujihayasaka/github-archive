# typed: true
# frozen_string_literal: true

class TransferIssueJob < ApplicationJob
  ALLOWED_CONCURRENT_JOBS_COUNT = 20

  queue_as :transfer_issue
  retry_on_dirty_exit
  retry_on_recoverable_exceptions
  retry_on WaitForReplication::DataUnavailable
  retry_on ActiveRecord::RecordInvalid # Retry job in case of race conditions in data creation.
  retry_on GitHub::Restraint::UnableToLock, wait: 5.minutes, attempts: 10

  locked_by timeout: 1.hour, key: ->(job) {
    # lock on the transfer object to make sure only 1 transfer per transfer object is running
    job.arguments[0]&.old_issue_id
  }

  # Discard the job if the subject or author are deleted before the job runs
  discard_on ActiveRecord::RecordNotFound

  def perform(issue_transfer, options = {})
    lock_key = "transfer_issue_job_per_actor_#{issue_transfer.actor_id}"
    concurrent_jobs = ALLOWED_CONCURRENT_JOBS_COUNT
    lock_ttl = 1.hour
    restraint = GitHub::Restraint.new
    restraint.lock!(lock_key, concurrent_jobs, lock_ttl) do
      GitHub::RateLimitedCreation.disable_content_creation_rate_limits do
        # First parameter is staff_user, then `create_labels_if_missing`
        with_write do
          issue_transfer.complete_transfer(create_labels_if_missing: create_labels_if_missing?(options))
        end
      end
    end
  end

  def logging_context
    super.merge(context)
  end

  def failbot_context
    context
  end

  def context
    return {} unless arguments&.first

    # There is no personally identifying information in TransferIssueJobs, so
    # we can use all the attributes.
    arguments.first
      .attributes
      .transform_keys { |key| "issue_transfer_#{key}" }
      .symbolize_keys
  end

  private

  def create_labels_if_missing?(options)
    options[:create_labels_if_missing].present? && options[:create_labels_if_missing]
  end
end
