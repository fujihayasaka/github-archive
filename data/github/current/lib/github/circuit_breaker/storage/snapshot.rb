# typed: true
# frozen_string_literal: true

# Note: this file omits type annotations because it is performance critical.

module GitHub
  module CircuitBreaker
    module Storage
      # A snapshot of the current state of the circuit breaker metrics.
      # Provides no safe-guards against negative values.
      class Snapshot
        # The number of successful actions taken by the circuit breaker for this snapshot.
        attr_reader :successes

        # The number of failed actions taken by the circuit breaker for this snapshot.
        attr_reader :failures

        # Initializes the snapshot with zero successes and failures.
        def initialize
          @successes = 0
          @failures = 0
        end

        # The total number of actions taken by the circuit breaker for this snapshot.
        def total
          @successes + @failures
        end

        # Updates the number of successful actions taken by the circuit breaker for this snapshot.
        # The default amount is 1, but any value (positive or negative) may be used.
        def increment_successes(amount = 1)
          @successes += amount
        end

        # Updates the number of failed actions taken by the circuit breaker for this snapshot.
        # The default amount is 1, but any value (positive or negative) may be used.
        def increment_failures(amount = 1)
          @failures += amount
        end

        # Updates this snapshot by subtracting the values from another snapshot.
        # The other snapshot is not modified.
        def decrement_by(other)
          @successes -= other.successes
          @failures -= other.failures
          nil
        end

        # Resets the snapshot to its initial state (i.e. all counts zeroed).
        def reset
          @successes = 0
          @failures = 0
          nil
        end
      end
    end
  end
end
