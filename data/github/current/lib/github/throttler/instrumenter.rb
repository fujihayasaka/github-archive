# typed: true
# frozen_string_literal: true

module GitHub
  module Throttler
    class Instrumenter
      # instruments the following events:
      #
      # - "throttler.called" each time this method is called
      # - "throttler.succeeded" when the stores were ok, before yielding the block
      # - "throttler.waited" when the stores were not ok, after waiting
      #   `wait_seconds`
      # - "throttler.waited_too_long" when the stores were not ok, but the
      #   thottler already waited at least `max_wait_seconds`, right before
      #   raising `WaitedTooLong`
      # - "throttler.freno_errored" when there was an error with freno, before
      #   raising `ClientError`.
      # - "throttler.circuit_open" when the circuit breaker does not allow the
      #   next request, before raising `CircuitOpen`
      #
      # Using the event name to delegate to the proper method if it is defined
      def instrument(event_name, payload)
        method = event_name.sub("throttler.", "")
        send(method, payload) if respond_to?(method)
      end
    end
  end
end
