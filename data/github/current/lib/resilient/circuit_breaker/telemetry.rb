# typed: true
# frozen_string_literal: true

module Resilient
  module CircuitBreakerTelemetry
    # Emits circuit breaker attributes to the given span.
    #
    # span    - The OpenTelemetry span to add attributes to.
    # circuit - The circuit breaker instance.
    # allowed - Whether the request was allowed (optional, for error status).
    #
    # Adds standard circuit breaker attributes to the span.
    def self.emit(span, circuit, allowed: true)
      unless allowed
        span.status = OpenTelemetry::Trace::Status.error("The request was rejected by the circuit breaker")
      end
      span.add_attributes(
        "circuit_breaker.key" => circuit.key.name,
        "circuit_breaker.error_threshold_percentage" => circuit.properties.error_threshold_percentage,
        "circuit_breaker.request_volume_threshold" => circuit.properties.request_volume_threshold,
        "circuit_breaker.window_size" => circuit.properties.window_size_in_seconds,
        "circuit_breaker.bucket_size" => circuit.properties.bucket_size_in_seconds,
        "circuit_breaker.circuit_open" => circuit.open,
        "circuit_breaker.current_error_percentage" => circuit.metrics.error_percentage,
        "circuit_breaker.total_requests" => circuit.metrics.requests,
      )
    end
  end
end
