# typed: true
# frozen_string_literal: true

module Api
  module Limiters
    module Internal
      class GraphQLRepeatedTimeout < Api::Limiters::GraphQLRepeatedTimeout

        sig { params(max: Integer, ttl: Integer).void }
        def initialize(max:, ttl:)
          super(max: max, ttl: ttl)
        end

        sig { override.params(request: Rack::Request).returns(T::Boolean) }
        def ignored?(request)
          # Proceed if we're blocking requests or collecting metrics. Both must be disabled to disable the limiter.
          return true unless graphql_request?(request)
          return true unless blocking_requests_enabled? || metrics_emission_enabled?
          false
        end

        # Overrides the name of the limiter to avoid conflicts with the public GraphQLRepeatedTimeout limiter.
        sig { override.returns(String) }
        def name
          "internal-graphql-repeated-timeout"
        end

        protected

        # Overrides the method to omit the IP address from the fingerprint.
        sig { override.params(request: Rack::Request).returns(T.nilable(String)) }
        def fingerprint(request)
          super(request, omit_ip: true)
        end

        sig { override.returns(T::Boolean) }
        def blocking_requests_enabled?
          GitHub.flipper[:internal_graphql_repeated_timeout_rate_limiter_blocking].enabled?
        end

        sig { override.returns(T::Boolean) }
        def metrics_emission_enabled?
          GitHub.flipper[:internal_graphql_repeated_timeout_rate_limiter_metrics].enabled?
        end

        # Overrides the method to return the log data prefix for the internal limiter.
        sig { override.returns(String) }
        def log_data_prefix
          "internal.graphql_repeated_timeout"
        end
      end
    end
  end
end
