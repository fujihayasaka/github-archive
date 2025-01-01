# typed: true
# frozen_string_literal: true

module Api
  module Limiters
    # This limiter is intialized with a maximum number of concurrent requests to
    # allow as well as a TTL.
    #
    # The TTL-based window can lead to slightly odd edge cases. If the limit
    # is 10 requests:
    #
    # * A request starts (and perhaps finishes), initializing the window key
    # * 10 requests begin
    # * Subsequent requests are blocked
    # * The window key expires
    # * New requests reinitialize and increment the key from 0
    # * The previous 10 requests now finish, decrementing the counter to a
    #   minimum value of 0 even though several requests are still being processed.
    #
    # At this point, for remainder of the TTL window, the limiter will allow
    # extra requests. The current implementation is about as simple as it gets,
    # but it can be adjusted in the future if this edge case shows up more often
    # than we think it will, or has a negative effect.
    #
    # A potential solution is to change from using a TTL on a fixed key, to a
    # time-based key (based on request timestamp).
    class ConcurrentAuthenticationFingerprint < GitHub::Limiters::MemcachedWindow
      include Api::Limiters::ObservabilityHelpers
      include Api::Limiters::Helpers

      LIMITER_LOG_PREFIX = "concurrent"
      RESET_DURATION = 1 # inform clients that they can retry nearly immediately

      IGNORED_PATHS = [
        %r{\A(/api/v3)?/rate_limit\z},
      ]

      def initialize(name = "concurrent-authentication-fingerprint", ttl:, max:)
        @max = max
        super(name, ttl: ttl, limit: max)
      end

      def record_start(request)
        current = increment_counter(request)

        if GitHub::Routers::Api.internal_api_host?(request.host) && GitHub.multi_tenant_enterprise?
          key = key(request)

          if (log_data = request.env[Rack::RequestLogger::APPLICATION_LOG_DATA])
            add_to_log_data(LIMITER_LOG_PREFIX, log_data, key, http_user_agent(request), nil, current, @max)
          end

          unless auth_type(request) == :other
            post_to_datadog(key, current, @max, kind: "concurrent")
          end
        end
      end

      def record_finish(request)
        decrement_counter(request)
      end

      def duration
        RESET_DURATION
      end

      def ignored?(request)
        IGNORED_PATHS.any? { |path_regex| request.path_info =~ path_regex }
      end

      protected

      def key(request)
        fingerprint(request)
      end
    end
  end
end
