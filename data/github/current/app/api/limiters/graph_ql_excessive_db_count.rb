# typed: true
# frozen_string_literal: true

module Api
  module Limiters
    class GraphQLExcessiveDBCount < GitHub::Limiters::MemcachedWindow
      extend T::Sig

      def initialize(max:, threshold:, ttl:)
        super("graphql-excessive-db-count", limit: max, ttl: ttl)
        @threshold = threshold
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
        @mysql_count
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
        @mysql_count = GitHub::MysqlInstrumenter.query_count
        exceeded_threshold = @mysql_count >= @threshold

        if exceeded_threshold
          # increment_counter(request) is defined in the super class.
          # it calls cost(request) and add the value to the cache.
          increment_counter(request)
        end

        if GitHub.flipper[:graphql_excessive_db_count_rate_limiter_metrics].enabled?
          tags = ["exceeded_threshold:#{exceeded_threshold}", "would_block:#{at_limit?(request)}"]

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
    end
  end
end
