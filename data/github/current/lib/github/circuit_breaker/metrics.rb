# typed: true
# frozen_string_literal: true
# Note: this file omits type annotations because it is performance critical.

require_relative "storage"

module GitHub
  module CircuitBreaker
    # An alternative metrics implementation for Resilient::CircuitBreaker.
    # Enables the use of a zero-allocation storage implementations by using an numeric-based monotonic clock.
    class Metrics
      # The default clock to use for measuring time in metrics.
      DEFAULT_CLOCK = proc { Process.clock_gettime(Process::CLOCK_MONOTONIC) }

      # Creates a new Metrics instance with the given storage for success and failure counts.
      # Supports a block that returns the a monotonic time in seconds since some epoch.
      # The clock defaults to the system monotonic clock.
      def initialize(storage:, &clock)
        @storage = storage
        @clock = clock || DEFAULT_CLOCK
      end

      # Returns the current monotonic time in seconds since some epoch.
      def now
        @clock.call
      end

      # Increment the number of successful actions taken by the circuit breaker at the current timestamp.
      def success
        @storage.increment_successes(now)
        nil
      end

      # Increment the number of failed actions taken by the circuit breaker at the current timestamp.
      def failure
        @storage.increment_failures(now)
        nil
      end

      # The count of successful actions taken by the circuit breaker in the current sliding window up to the current timestamp.
      def successes
        @storage.successes(now)
      end

      # The count of failed actions taken by the circuit breaker in the current sliding window up to the current timestamp.
      def failures
        @storage.failures(now)
      end

      # The total count of actions taken by the circuit breaker in the current sliding window up to the current timestamp.
      def requests
        @storage.total(now)
      end

      # The percentage of failed requests in the current sliding window up to the current timestamp.
      # Storage implementations are guaranteed to receive the exact same timestamp for all calls in this method to aid in memoization.
      def error_percentage
        timestamp = now

        requests = @storage.total(timestamp)
        return 0 if requests == 0

        failures = @storage.failures(timestamp)
        return 0 if failures == 0

        (100.0 * failures / requests).round
      end

      # Resets the current metrics to its initial state (i.e. an empty sliding window).
      def reset
        @storage.reset
        nil
      end
    end
  end
end
