# typed: true
# frozen_string_literal: true

module Api
  module Limiters
    class GraphQLRepeatedTimeout < GitHub::Limiters::MemcachedWindow
      include GitHub::Memoizer
      include Api::Limiters::ObservabilityHelpers
      include Api::Limiters::Helpers
      include Api::Limiters::GraphqlHelper

      sig { params(max: Integer, ttl: Integer).void }
      def initialize(max:, ttl:)
        super(name, limit: max, ttl: ttl)
      end

      sig { override.params(request: Rack::Request).returns(State) }
      def start(request)
        # Only limit if blocking requests is enabled.
        if blocking_requests_enabled? && at_limit?(request)
          State.new limited: true, duration: @ttl, glb: @glb
        else
          OK
        end
      end

      # ignored?(request) determines if the request should be ignored by the rate limiter.
      sig { override.params(request: Rack::Request).returns(T::Boolean) }
      def ignored?(request)
        # Proceed if we're blocking requests or collecting metrics. Both must be disabled to disable the limiter.
        return true unless graphql_request?(request)
        return true unless blocking_requests_enabled? || metrics_emission_enabled?
        false
      end

      # key(request) defines the cache key for the request.
      # it returns the user fingerprint from the request.
      sig { override.params(request: Rack::Request).returns(T.nilable(String)) }
      def key(request)
        fingerprint(request)
      end

      # record_finish_with_timeout(request) is called at the end of a request that timed out.
      # This method increments the dogstats metric if the FF is enabled, tagged with:
      #   1. timed out
      #   2. its blockage state
      sig { params(request: Rack::Request).void }
      def record_finish_with_timeout(request)
        if metrics_emission_enabled?
          tags = ["timeout:true", "blocked:#{at_limit?(request)}"]
          # report to DD timed out = true and blocked = false/true
          GitHub.dogstats.increment(
            "limiters.#{log_data_prefix}",
            tags: tags
          )
        end

        increment_counter(request)
      end

      # record_finish(request) is called at the end of a request that didn't time out by finish(request) defined in
      # the super class.
      # This method increments the dogstats metric if the FF is enabled, tagged with:
      #   1. not timed out
      #   2. its blockage state
      sig { override.params(request: Rack::Request).void }
      def record_finish(request)
        if metrics_emission_enabled?
          tags = ["timeout:false", "blocked:#{at_limit?(request)}"]
          # report to DD timed out = false and blocked = false/true
          GitHub.dogstats.increment(
            "limiters.#{log_data_prefix}",
            tags: tags
          )
        end
      end

      # graphql_request?(request) determines if the request is a graphql request.
      sig { params(request: Rack::Request).returns(T::Boolean) }
      def graphql_request?(request)
        fingerprint = fingerprint(request)
        return false if fingerprint.nil? || fingerprint.empty?
        super(request)
      end

      sig { override.returns(String) }
      def name
        "graphql-repeated-timeout"
      end

      # timeout overrides the limiter timeout handling.
      sig { override.params(env: T.untyped).void }
      def timeout(env)
        # Use a new memcached instance because when a timeout occurs, the
        # existing memcached client's state is undefined.
        with_new_memcached_instance do
          request = Rack::Request.new(env)
          record_finish_with_timeout(request)
        end
      end

      sig { returns(T::Boolean) }
      def blocking_requests_enabled?
        GitHub.flipper[:graphql_repeated_timeout_rate_limiter_blocking].enabled?
      end

      sig { returns(T::Boolean) }
      def metrics_emission_enabled?
        GitHub.flipper[:graphql_repeated_timeout_rate_limiter_metrics].enabled?
      end

      protected

      # The intention is that this gets overridden by the internal limiter.
      sig { returns(String) }
      def log_data_prefix
        "graphql_repeated_timeout"
      end
    end
  end
end
