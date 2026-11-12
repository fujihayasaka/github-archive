# frozen_string_literal: true

module Freno
  class ThrottlerInstrumenter
    PREFIX = "freno.throttler"

    # instrumenter.instrument("throttler.#{event_name}", payload, &block

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
    def instrument(event_name, payload = {})
      method = event_name.sub("throttler.", "")
      send(method, payload) if respond_to?(method)
    end

    # responds to event "throttler.called"
    def called(payload)
      MetricsClient.increment(with_prefix("called"), tags: tags_from(payload))
    end

    # responds to event "throttler.waited"
    def waited(payload)
      MetricsClient.histogram(with_prefix("waited"), payload[:waited], tags: tags_from(payload))
    end

    # responds to event "throttler.waited_too_long"
    def waited_too_long(payload)
      MetricsClient.increment(with_prefix("timed_out"), tags: tags_from(payload))
    end

    # responds to event "throttler.freno_errored"
    def freno_errored(payload)
      MetricsClient.increment(with_prefix("freno_error"), tags: tags_from(payload))
    end

    # responds to event "throttler.circuit_open"
    def circuit_open(payload)
      MetricsClient.increment(with_prefix("circuit_open"), tags: tags_from(payload))
    end

    private

    def with_prefix(stat)
      "#{PREFIX}.#{stat}"
    end

    def tags_from(payload)
      cluster_names = payload[:store_names] || []
      { cluster: cluster_names.sort.join(",") }
    end
  end
end
