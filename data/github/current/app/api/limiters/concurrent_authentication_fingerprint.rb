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
      include Api::Limiters::Helpers
      include Api::Limiters::TwirpHelpers

      LIMITER_LOG_PREFIX = "concurrent"
      RESET_DURATION = 1 # inform clients that they can retry nearly immediately

      IGNORED_PATHS = [
        %r{\A(/api/v3)?/rate_limit\z},
      ]

      def initialize(name = "concurrent-authentication-fingerprint", ttl:, max:)
        @max = max
        super(name, ttl: ttl, limit: max)
      end

      def start(request)
        super(request)
      end

      def record_start(request)
        increment_counter(request)
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
