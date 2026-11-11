# typed: false
# frozen_string_literal: true

require "github/throttler"

class BaseHelpers
  # Internal: A set of methods delegating throttling methods to the correct throttler instance.
  #
  # This module depends on an instance method `.connection`.
  module Helpers
    # Let's add these methods to the class and instances
    def self.included(base)
      base.extend(self)
    end

    # Public: Attempts to retry the query if the record is not unique
    #
    # on_max_retry - optional proc to call when the maximum number of retries is reached
    #
    # Returns the result of the provided block.
    def retry_on_find_or_create_error(max_retry_count: 1, on_max_retry: nil)
      retry_count = 0
      begin
        yield
      rescue ActiveRecord::RecordNotUnique
        retry_count += 1
        if retry_count > max_retry_count
          if on_max_retry.respond_to? :call
            on_max_retry.call
          else
            raise
          end
        else
          retry
        end
      end
    end

    # Attempts to retry the query if deadlock occurs.
    #
    # max_retry_count: - The number of times to retry before giving up.
    # backoff: - Maximum base jitter in seconds for sleep between retries. When 0 (default), retries immediately
    #            with no delay. When > 0, sleeps `retry_count * rand(0.0..backoff)` seconds between attempts, adding
    #            linear backoff with random jitter to avoid thundering herd when multiple processes contend on the
    #            same rows. A value of 0.1 yields ~0-0.8s per retry (up to ~0.8s on retry #8), with up to ~3.6s
    #            total worst-case sleep (average ~1.8s) across 8 retries. Useful when reliability matters more
    #            than latency under high concurrency (e.g., Gauntlet failures due to deadlocks during test setup).
    def retry_on_deadlock(max_retry_count: 8, backoff: 0)
      retry_count = 0
      begin
        yield
      rescue ActiveRecord::Deadlocked
        retry_count += 1
        raise if retry_count > max_retry_count
        sleep(retry_count * rand(0.0..backoff)) if backoff > 0
        retry
      end
    end

    # Attempts to retry the statement if statement invalid occurs
    #
    # max_retry_count: - The number of times to retry before giving up
    def retry_on_statement_invalid(max_retry_count: 5)
      retry_count = 0
      begin
        yield
      rescue ActiveRecord::StatementInvalid
        retry_count += 1
        retry_count > max_retry_count ? raise : retry
      end
    end
  end
end
