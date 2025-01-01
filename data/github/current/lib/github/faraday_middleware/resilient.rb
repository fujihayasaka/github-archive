# typed: true
# frozen_string_literal: true

# This module provides Faraday Middleware that allows us to introduce circuit-breakers on our Faraday calls
# This Middleware should be instrumented _after_ any retry middleware in order to instrument retry attempts. As the circuit-breaker adds specific headers
# and error messages to the response, if the circuit breaker has opened, our retry-middleware will need to respect this
# information
#
# Example configuration:
# circuit_breaker_name = "my-cool-circuit-breaker"
#
# conn = Faraday.new(url: "http://localhost:9292") do |c|
#     c.request :retry,
#               {
#                 # See https://github.com/lostisland/faraday/blob/v0.17.6/lib/faraday/request/retry.rb for a list
#                 # of all available configurations
#                 methods: [], # by default, Faraday sets this to `[:delete, :get, :head, :options, :put]`,
#                              # when a method is present in this `methods` array, Faraday skips the `retry_if` block
#                              # when determining if it should retry or not
#                 retry_if: proc { |env, _excp|
#                   # Our Resilient Middleware returns 502 w/ headers { Resilient: yes } when the circuit is open
#                   # if the error _is_ caused by a CircuitBreaker, _or_ the circuit breaker has opened since the failure
#                   # then we don't want to retry
#                   open_breaker_response = env.response_headers["Resilient"] == "yes" && env.status == 502
#                   circuit_breaker = Resilient::CircuitBreaker.get(circuit_breaker_name)
#
#                   !open_breaker_response && circuit_breaker.allow_request?
#                 }
#               }
#     c.response :raise_error # https://lostisland.github.io/faraday/#/middleware/included/raising-errors
#     c.use GitHub::FaradayMiddleware::Resilient,
#       name: "my-circuit-breakers-cool-name", # e.g. stripe-enterprise-payment, for a faraday client that is built to
#                                              # talk to stripe and process enterprise payments :thumbs-up:
#       options: {
#         # See https://github.com/jnunemaker/resilient/blob/v0.4.0/lib/resilient/circuit_breaker/properties.rb for a
#         # list of all configurations Resilient::CircuitBreaker takes
#         #
#         # These options need to be tuned to the use case of the circuit breaker, e.g.
#         # if my service has an average of 100request/second/process, then my `request_volume_threshold` should not be
#         #   something like 300, as we will not hit that, and the circuit breakers rely on meeting the request_threshold
#         #   before opening, _along side_ the error threshold,
#         #   i.e. if my request_threshold = 200
#         #              error_threshold = 50%
#         #   and I am seeing 100% error_threshold but only 100 requests/second, my breaker wont open
#         request_volume_threshold: <INT>,
#         error_threshold_percentage: <INT>,
#         window_size_in_seconds: <INT>,
#         bucket_size_in_seconds: <INT>,
#         sleep_window_seconds: <INT>,
#       }
#
#     c.adapter Faraday.default_adapter
# end
module GitHub
  module FaradayMiddleware
    class Resilient < Faraday::Middleware
      def self.tripped?(res)
        res.status == 502 && res.headers[:resilient] == "yes"
      end

      def initialize(app, options, &block)
        super(app)
        @name = options[:name]
        @options = options[:options] || {}
        @options[:instrumenter] = ::ActiveSupport::Notifications unless options.include?(:instrumenter)
        @registry = options[:registry]
        @tripped_request_block = block
      end

      def circuit_breaker
        ::Resilient::CircuitBreaker.get(@name, @options, @registry)
      end

      def call(env)
        GitHub.tracer.in_span("gh.resilient.faraday_client.request") do
          env.clear_body if env.needs_body?
          circuit = circuit_breaker
          allowed = circuit.allow_request?

          emit_telemetry(allowed, circuit)
          if allowed
            call_request(env, circuit)
          else
            tripped_request(env, circuit)
          end
        end
      end

      def call_request(env, circuit)
        @app.call(env).on_complete do |response_env|
          status = response_env[:status]
          if status < 200 || status > 499
            circuit.failure
          else
            circuit.success
          end
        end
      rescue # rubocop:todo Lint/GenericRescue
        circuit.failure
        raise
      end

      def tripped_request(env, circuit)
        env[:resilient_circuit] = circuit
        env.status = 502
        env.response_headers = ::Faraday::Utils::Headers.new
        env.response_headers["Resilient"] = "yes"
        env.response = ::Faraday::Response.new

        # With Faraday 0.x `env.body` continues to return the request body if we
        # never set a response body. Twirp then parses that as if it is a
        # response body.
        #
        # With Faraday 1.x `env.body` always returns the response body once the
        # status is set.  Twirp can't handle a `nil` body on error (it tries to
        # parse it as JSON and ends up with an unhandled `TypeError`):
        # https://github.com/arthurnn/twirp-ruby/blob/c9c8b5ea9a74238f66151f03148004e27ccacaaa/lib/twirp/client.rb#L48-L72
        #
        # So this sets an arbitrary value for the response body for now.
        # If we can fix twirp to handle a `nil` body on error, we should be able
        # to remove this line after upgrading to Faraday v1.x.
        env.body = ""

        @tripped_request_block&.call(env)

        env.response.finish(env) unless env.parallel?

        env.response
      end

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
