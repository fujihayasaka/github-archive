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

    # Retries the block if a deadlock occurs.
    #
    # This can wrap transactions that are safe to retry. See
    # https://thehub.github.com/epd/engineering/products-and-services/dotcom/deadlocked-transactions/
    #
    # It can also be used to retry individual queries outside of transactions.
    #
    # This cannot be used to retry individual queries within a transaction or
    # nested transactions (since the deadlock rolls back the transaction
    # and the retry would then happen without a wrapping transaction).
    #
    # max_retry_count: - The number of times to retry before giving up. This should be as low as possible.
    # backoff: - Maximum base jitter in seconds for sleep between retries. When 0, retries immediately
    #            with no delay. When > 0, sleeps `retry_count * rand(0.0..backoff)` seconds between attempts, adding
    #            linear backoff with random jitter to avoid thundering herd when multiple processes contend on the
    #            same rows. A value of 0.1 yields ~0-0.1s on the first retry, ~0-0.2s on the second, etc.
    def retry_on_deadlock(max_retry_count: 1, backoff: 0.1, source: nil)
      retry_count = 0
      begin
        yield
      rescue ActiveRecord::Deadlocked
        # This method can be called on the class or an instance
        klass = self.is_a?(Class) ? self : self.class
        raise if klass.connection.open_transactions != BASELINE_TRANSACTION_COUNT

        retry_count += 1
        raise if retry_count > max_retry_count

        # Doesn't get us the exact source, but in most cases there's only 1 call
        # per file and this should get us close enough
        source ||= File.basename(caller_locations(2, 1).first.path, ".rb")
        GitHub.dogstats.increment("rpc.mysql.deadlock_retry.count", tags: ["retry_count:#{retry_count}", "source:#{source}"])

        sleep(retry_count * rand(0.0..backoff)) if backoff > 0
        retry
      end
    end

    # Allow for the outer fixtures transaction in test
    BASELINE_TRANSACTION_COUNT = GitHub::AppEnvironment.test? ? 1 : 0
  end
end
