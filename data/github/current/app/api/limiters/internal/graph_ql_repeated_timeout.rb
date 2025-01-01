# typed: true
# frozen_string_literal: true

module Api
  module Limiters
    module Internal
      class GraphQLRepeatedTimeout < Api::Limiters::GraphQLRepeatedTimeout

        # Regex for the Launch user agent.
        ACTIONS_LAUNCH_USER_AGENT_REGEX = /\Alaunch\/(production|lab|development|test)\z/.freeze

        sig { params(max: Integer, ttl: Integer).void }
        def initialize(max:, ttl:)
          super(max: max, ttl: ttl)
        end

        sig { override.params(request: Rack::Request).returns(State) }
        def start(request)
          # call parent class's start method on request
          if is_exempt_internal_client?(request)
            return OK
          end
          super(request)
        end

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
          fingerprint(request, omit_ip: true)
        end


        # Overrides the name of the limiter to avoid conflicts with the public GraphQLRepeatedTimeout limiter.
        sig { override.returns(String) }
        def name
          "internal-graphql-repeated-timeout"
        end

        protected

        # get user agent from the request header
        sig { params(env: T::Hash[String, T.untyped]).returns(T.nilable(String)) }
        def get_http_user_agent(env)
          env[GitHub::Middleware::Constants::HTTP_USER_AGENT]
        end


        sig { override.returns(T::Boolean) }
        def blocking_requests_enabled?
          GitHub.flipper[:internal_graphql_repeated_timeout_rate_limiter_blocking].enabled?
        end

        sig { override.returns(T::Boolean) }
        def metrics_emission_enabled?
          GitHub.flipper[:internal_graphql_repeated_timeout_rate_limiter_metrics].enabled?
        end

        # check the request header to see if the http agent matches the regex for Actions
        # this is a temporary solution until we can figure out a more permanent solution
        # see: https://github.com/github/graphql-platform/issues/1427
        sig { params(request: Rack::Request).returns(T::Boolean) }
        def is_exempt_internal_client?(request)
          user_agent = get_http_user_agent(request.env)
          is_actions_launch = ACTIONS_LAUNCH_USER_AGENT_REGEX.match?(user_agent)

          # if this FF is enabled, then exempt the request
          if GitHub.flipper[:internal_graphql_repeated_timeout_rate_limiter_exempt_launch].enabled?
            return true if is_actions_launch
          end
          false
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
