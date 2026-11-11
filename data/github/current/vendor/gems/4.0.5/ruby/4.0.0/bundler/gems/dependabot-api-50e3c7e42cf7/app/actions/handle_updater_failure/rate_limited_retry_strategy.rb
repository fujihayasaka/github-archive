# frozen_string_literal: true

# Extends the default retry strategy to make 3 retry attempts with an expontential backoff
# that accounts for rate limit reset times from the dotcom response.
class HandleUpdaterFailure
  class RateLimitedRetryStrategy < DefaultRetryStrategy
    MAX_JITTER = 600

    private

    # # octokit_rate_limited are retried 3 times, others only get retried once
    def retries_exceeded?
      update_job_retry_attempts >= 3
    end

    def wait
      expires_at = rate_limited_error.error_details["rate-limit-reset"].to_i
      remaining = Time.at(expires_at).in_time_zone - Time.now.in_time_zone
      # Fall back to waiting 3 minutes if no reset is found
      remaining = remaining.positive? ? remaining : 180
      attempts = update_job_retry_attempts # Between 0 and 2
      # Add some backoff between 3 and 67 mins based on attempts
      backoff = (attempts**2 * 16 * 60) + 180
      # Jitter between 0 and 10 mins so we don't retry failed jobs
      # from the same org all at once
      jitter = rand(0..MAX_JITTER)
      backoff.seconds + jitter.seconds + remaining.seconds
    end

    def rate_limited_error
      return @rate_limited_error if defined?(@rate_limited_error)

      @rate_limited_error =
        update_job.update_job_errors.find do |e|
          e.error_type == "octokit_rate_limited"
        end
    end
  end
end
