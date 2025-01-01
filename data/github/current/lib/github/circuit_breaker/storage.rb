# typed: true
# frozen_string_literal: true

# Note: this file omits type annotations because it is performance critical.

module GitHub
  module CircuitBreaker
    # A marker module that represents a storage implementation for circuit breaker metrics.
    module Storage
      include Kernel

      # Increments the number of successful actions taken by the circuit breaker at the given timestamp (in seconds since some epoch).
      # The default amount is 1, but any value (positive or negative) may be used.
      def increment_successes(now, amount: 1)
        raise NotImplementedError
      end

      # Increments the number of failed actions taken by the circuit breaker at the given timestamp (in seconds since some epoch).
      # The default amount is 1, but any value (positive or negative) may be used.
      def increment_failures(now, amount: 1)
        raise NotImplementedError
      end

      # The count of successful actions taken by the circuit breaker in the current sliding window up to the given timestamp (in seconds since some epoch).
      def successes(now)
        raise NotImplementedError
      end

      # The count of failed actions taken by the circuit breaker in the current sliding window up to the given timestamp (in seconds since some epoch).
      def failures(now)
        raise NotImplementedError
      end

      # The total count of actions taken by the circuit breaker in the current sliding window up to the given timestamp (in seconds since some epoch).
      def total(now)
        raise NotImplementedError
      end

      # Resets the storage to its initial state (i.e. an empty sliding window).
      def reset
        raise NotImplementedError
      end
    end
  end
end
