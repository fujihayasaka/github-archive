# typed: true
# frozen_string_literal: true

# Checks the status of asynchronous batch jobs sent to Mailchimp, and re-enqueues itself with
# an exponential backoff until the job is no longer pending
class MailchimpBatchStatusJob < ApplicationJob
  queue_as :mailchimp

  RetryableError = Class.new(RuntimeError)
  retry_on RetryableError, attempts: 3

  def perform(batch_id, options = {})
    @batch_id = batch_id
    @options = options

    with_mailchimp_retries do
      batch = GitHub::Mailchimp.find_batch(@batch_id)
      if batch["status"] == "finished"
        GitHub.dogstats.increment("mailchimp", tags: ["job:batch_status", "type:finished"])

        return if batch["errored_operations"] == 0
        raise GitHub::Mailchimp::BatchError.new(batch), error_message
      else
        retry_job
      end
    end
  end

  # Public: When Mailchimp API calls fail due to 5xx server errors,
  # retry the call up to 25 times. Otherwise, raise an exception
  # and fail the job.
  def with_mailchimp_retries(&block)
    yield
  rescue GitHub::Mailchimp::Error => boom
    if GitHub::Mailchimp::ServerErrorStatuses.include?(boom.status_code)
      GitHub.dogstats.increment "mailchimp", tags: ["job:batch_status", "try:retry"]
      raise RetryableError
    else
      raise
    end
  end

  private

  def error_message
    "There were errored operations among the Mailchimp batched operations."
  end
end
