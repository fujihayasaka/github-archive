# typed: strict
# frozen_string_literal: true

# Based on GitHub::FaradayMiddleware::Resilient with specific configurations
# for Alloy.
module Alloy
  module FaradayMiddleware
    class CircuitBreaker < Faraday::Middleware
      sig { params(app_name: String).returns(Resilient::CircuitBreaker) }
      def circuit_breaker(app_name)
        Resilient::CircuitBreaker.get("alloy.#{app_name}", {
          instrumenter: GitHub,
          # number of requests that must be made within a statistical window
          # before open/close decisions are made using stats
          request_volume_threshold: 5,
          # Seconds after tripping circuit before allowing retry
          sleep_window_seconds: 10,
          # % of "marks" that must be failed to trip the circuit
          error_threshold_percentage: 5,
          # Number of seconds in the statistical window
          window_size_in_seconds: 30,
          # Size of buckets in statistical window
          bucket_size_in_seconds: 5,
        })
      end

      sig { params(env: Faraday::Env).returns(T.any(Faraday::Response, ConcurrentFaraday::FutureResponse[Faraday::Response])) }
      def call(env)
        GitHub.tracer.in_span("gh.alloy.faraday_client.request") do
          app_name = T.unsafe(env).request_headers[Alloy::Constants::REACT_APP_HEADER]
          env.clear_body if env.needs_body?

          circuit = circuit_breaker(app_name)
          allowed = circuit.allow_request?

          emit_telemetry(allowed, circuit)
          if allowed
            call_request(env, circuit)
          else
            tripped_request(env, circuit)
          end
        end
      end

      sig { params(env: Faraday::Env, circuit: Resilient::CircuitBreaker).returns(T.any(Faraday::Response, ConcurrentFaraday::FutureResponse[Faraday::Response])) }
      def call_request(env, circuit)
        app.call(env).on_complete do |response_env|
          status = response_env[:status]
          if status < 200 || status > 399
            circuit.failure
          else
            circuit.success
          end
        end
      rescue # rubocop:todo Lint/GenericRescue
        circuit.failure
        raise
      end

      sig { params(env: Faraday::Env, circuit: Resilient::CircuitBreaker).returns(Faraday::Response) }
      def tripped_request(env, circuit)
        env = T.unsafe(env)
        env[:resilient_circuit] = circuit
        env.status = 502
        env.response_headers = ::Faraday::Utils::Headers.new
        env.response_headers["Resilient"] = "yes"
        env.body = "CircuitBreaker is open"
        if env.parallel?
          env.response = ::Faraday::Response.new(env)
        else
          env.response = ::Faraday::Response.new
          env.response.finish(env)
        end

        env.response
      end

      sig { params(allowed: T::Boolean, circuit: Resilient::CircuitBreaker).void }
      def emit_telemetry(allowed, circuit)
        span = GitHub.current_span
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
end
