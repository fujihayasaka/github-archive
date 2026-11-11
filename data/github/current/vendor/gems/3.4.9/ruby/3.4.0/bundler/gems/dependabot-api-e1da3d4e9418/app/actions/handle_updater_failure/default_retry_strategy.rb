# frozen_string_literal: true

# Makes a single attempt to retry a job without a backoff wait time.
class HandleUpdaterFailure
  class DefaultRetryStrategy
    DEFAULT_RETRY_WAIT = 0

    attr_reader :update_job

    def initialize(update_job)
      @update_job = update_job
    end

    def retriable?
      !retries_exceeded?
    end

    def retry!
      return false unless retriable?

      update_job.retry!(wait: wait)
      true
    end

    private

    def wait
      DEFAULT_RETRY_WAIT
    end

    def retries_exceeded?
      update_job_retry_attempts >= 1
    end

    def update_job_retry_attempts
      update_job.update_job_transitions.map(&:to_state).
        count { |state| state == "pending_retry" }
    end
  end
end
