# typed: true
# frozen_string_literal: true

module Api
  module Limiters
    class GraphQLExcessiveDBCount < GitHub::Limiters::MemcachedWindow
      MOBILE_CLIENT_APPS_REGEX = /\w+\/(\d*\W){3}\(com.github.(stormbreaker.prod(.\w+)*|android); build:[0-9]+; (iOS|Android) (\d+.\d+.\d+|\d+)*; \w+(,\d+)*\)/.freeze
      CLI_CLIENT_APPS_REGEX = /GitHub CLI \d+\.\d+\.\d+/.freeze

      def initialize(max:, threshold:, ttl:)
        super("graphql-excessive-db-count", limit: max, ttl: ttl)
        @threshold = threshold
        @is_client_app = false
      end

      def start(request)
        @is_client_app = false

        if !is_exempt_user_agent?(request) && at_limit?(request)
          State.new limited: true, duration: duration, glb: @glb
        else
          record_start(request)
          OK
        end
      end

      # record_start(request) is called at the beginning of a request
      # it will reset the mysql_count to 0 at the beginning of the request
      sig { params(request: Rack::Request).void }
      def record_start(request)
        @mysql_count = 0
      end

      # ignored?(request) determines if the request should be ignored by the rate limiter.
      def ignored?(request)
        return true unless graphql_request?(request)
        return true unless GitHub.flipper[:graphql_excessive_db_count_rate_limiter].enabled?
        false
      end

      # key(request) defines the cache key for the request.
      # it returns the user fingerprint from the request.
      sig { params(request: Rack::Request).returns(T.nilable(String)) }
      def key(request)
        Api::Middleware::RequestAuthenticationFingerprint.get(request.env).to_s
      end

      # cost(request) defines the value to increment the cache with.
      # it returns the amount of mysql queries called from the request.
      sig { params(request: Rack::Request).returns(Integer) }
      def cost(request)
        GitHub::MysqlInstrumenter.query_count
      end

      # record_finish(request) is called at the end of a request
      # by finish(request) defined in the super class.
      # This method:
      #   1. grabs the number of mysql queries from the instrumenter
      #   2. checks if the number of mysql queries exceeded the threshold
      #   3. increments the counter if the threshold was exceeded
      #   4. increments the dogstats metric if the FF is enabled
      sig { params(request: Rack::Request).void }
      def record_finish(request)
        @mysql_count = cost(request)
        exceeded_threshold = @mysql_count >= @threshold

        if exceeded_threshold
          # increment_counter(request) is defined in the super class.
          # it calls cost(request) and add the value to the cache.
          increment_counter(request)
        end

        if GitHub.flipper[:graphql_excessive_db_count_rate_limiter_metrics].enabled?
          tags = [
            "exceeded_threshold:#{exceeded_threshold}",
            "blocked:#{at_limit?(request)}",
            "is_client_app:#{@is_client_app}"
          ]

          GitHub.dogstats.increment(
            "limiters.graphql_excessive_db_count",
            tags: tags
          )
        end
      end

      # graphql_request?(request) determines if the request is a graphql request.
      # it is not a graphql request if:
      #   1. the request method is not POST
      #   2. the request is missing an authentication fingerprint
      #   3. the request path is not a graphql path (e.g. /graphql or /api/graphql)
      sig { params(request: Rack::Request).returns(T::Boolean) }
      def graphql_request?(request)
        return false if request.request_method != "POST"
        return false if Api::GraphQL::PATH_REGEX.match(request.path_info).nil?
        return false if Api::Middleware::RequestAuthenticationFingerprint.get(request.env).nil?
        true
      end

      # check the request header to see if the http agent matches the regex for the client apps
      # this is a temporary solution until we can figure out a more permanent solution
      # see: https://github.com/github/graphql-platform/issues/850
      sig { params(request: Rack::Request).returns(T::Boolean) }
      def is_exempt_user_agent?(request)
        user_agent = get_http_user_agent(request.env)

        # we want to match regex no matter what for logging metrics
        is_mobile = !MOBILE_CLIENT_APPS_REGEX.match(user_agent).nil?
        is_cli = !CLI_CLIENT_APPS_REGEX.match(user_agent).nil?

        @is_client_app = is_mobile || is_cli

        # if this FF is enabled, then allow exemption for all client apps
        if GitHub.flipper[:graphql_excessive_db_count_rate_limiter_exempt_client_apps].enabled?
          return true if is_mobile

          # CLI can only be exempt if both FFs are enabled
          if GitHub.flipper[:graphql_excessive_db_count_rate_limiter_exempt_cli].enabled?
            return true if is_cli
          end
        end
        false
      end

      # get user agent from the request header
      sig { params(env: T::Hash[String, T.untyped]).returns(T.nilable(String)) }
      def get_http_user_agent(env)
        env[GitHub::Middleware::Constants::HTTP_USER_AGENT]
      end
    end
  end
end
