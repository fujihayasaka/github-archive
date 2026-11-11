# typed: true
# frozen_string_literal: true

module GitHub
  module Billing
    module ZuoraRateLimitHandler
      ZUORA_RATE_LIMIT_MAX_ATTEMPTS = 7
      EXECUTIONS_KEY = [Zuorest::TooManyRequestsError].to_s

      def zuora_rate_limit_handler(job, error, max_attempts = ZUORA_RATE_LIMIT_MAX_ATTEMPTS)
        # Keep track of the number of attempts made for this specific exception
        job.exception_executions[EXECUTIONS_KEY] = (job.exception_executions[EXECUTIONS_KEY] || 0) + 1
        attempts = job.exception_executions[EXECUTIONS_KEY]

        # Log some metrics and data
        rate_limit_type = error.rate_limit_remaining == 0 ? "window" : "concurrent"
        tags = job.all_stats_tags + ["class:#{job.class.name.underscore}", "rate_limit_type:#{rate_limit_type}", "attempts:#{attempts}"]
        GitHub.dogstats.increment("billing.zuora_rate_limit_error", tags: tags)

        GitHub.logger.info(
          "code.namespace" => "GitHub::Billing::ZuoraRateLimitHandler",
          "code.function" => "zuora_rate_limit_handler",
          "gh.billing.zuora.rate_limit_reset" => error.rate_limit_reset,
          "gh.billing.zuora.http.headers" => error.headers,
          "gh.job.name" => job.class.name,
          "gh.job.attempts" => attempts,
        )

        # Do nothing if we've already hit the max number of attempts.
        return unless attempts < max_attempts

        if rate_limit_type == "window"
          # We've exhaused our per minute/hour/day limit, wait until the rate limit resets
          job.retry_job(wait: error.rate_limit_reset)
        else
          # We're hitting the concurrent request limit, use a random wait time from exponentially
          # large wait intervals. This gives the following wait times at the end of each attempt:
          #
          # Attempt 1: min_wait = 1, max_wait = 2
          # Attempt 2: min_wait = 2, max_wait = 4
          # Attempt 3: min_wait = 4, max_wait = 8
          # Attempt 4: min_wait = 8, max_wait = 16
          # Attempt 5: min_wait = 16, max_wait = 32
          # Attempt 6: min_wait = 32, max_wait = 64
          #
          # This strategy ensures that when there are many requests failing at the same time, we
          # don't attempt to retry them all together at once. Instead, this should give us an
          # even spread of wait times to maximize the chance of success.
          min_wait = 2**(attempts - 1)
          max_wait = min_wait * 2
          job.retry_job(wait: Kernel.rand(min_wait..max_wait).minutes)
        end
      end
    end
  end
end
