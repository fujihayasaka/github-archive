# typed: true
# frozen_string_literal: true

require "resilient/circuit_breaker"

module Hydro
  class CircuitBreakingSink
    extend Forwardable

    def_delegators :sink,
      :add_to_batch,
      :batchable?,
      :batching?,
      :close,
      :flushable?,
      :messages,
      :start_batch,

    def self.circuit_breaker
      return @circuit_breaker if defined?(@circuit_breaker)

      options = {
        # seconds after tripping circuit before allowing retry
        sleep_window_seconds: 5,
        # number of requests that must be made within a statistical window
        # before open/close decisions are made using stats
        request_volume_threshold: 5,
        # % of "marks" that must be failed to trip the circuit
        error_threshold_percentage: 50,
        # number of seconds in the statistical window
        window_size_in_seconds: 30,
        # size of buckets in statistical window
        bucket_size_in_seconds: 5,
      }

      options[:instrumenter] = GitHub if GitHub.respond_to?(:instrument)

      @circuit_breaker = Resilient::CircuitBreaker.get("publish_hydro_events", options)
    end

    attr_reader :sink

    def initialize(sink, circuit_breaker: self.class.circuit_breaker, tags: [])
      @sink = sink
      @circuit_breaker = circuit_breaker
      @tags = tags
    end

    def write(messages, options = {})
      # ignore buffer writes for circuit breaker statistics
      if batching?
        return sink.add_to_batch(messages)
      end

      if circuit_breaker.allow_request?
        result = sink.write(messages, options)

        if result.success?
          circuit_breaker.success
        elsif !result.error.kind_of?(Hydro::Sink::MessagesTooLarge)
          circuit_breaker.failure
          GitHub.dogstats.count("hydro_client.publish.messages_dropped", messages.size, tags: @tags)
        end

        result
      else
        GitHub.dogstats.count("hydro_client.publish.messages_dropped", messages.size, tags: @tags)
        Hydro::Sink::Result.failure(Hydro::Sink::Error.new("breaker open"))
      end
    end

    def flush_batch
      if circuit_breaker.allow_request?
        result = sink.flush_batch

        if result.success?
          circuit_breaker.success
        elsif !result.error.kind_of?(Hydro::Sink::MessagesTooLarge)
          circuit_breaker.failure
          GitHub.dogstats.increment("hydro_client.publish.flush_failed")
        end

        result
      else
        GitHub.dogstats.increment("hydro_client.publish.flush_failed")
        Hydro::Sink::Result.failure(Hydro::Sink::Error.new("breaker open"))
      end
    end

    private

    attr_reader :circuit_breaker
  end
end
