# typed: true
# frozen_string_literal: true

module Api
  module Limiters
    module Internal
      class ConcurrentAuthenticationFingerprint < GitHub::Limiters::MemcachedWindow
        include Api::Limiters::Internal::RateLimitModulator
        include Api::Limiters::Helpers
        include Api::Limiters::Internal::RateLimitModulator
        include Api::Limiters::TwirpHelpers

        LIMITER_LOG_PREFIX = "internal.concurrent"
        RESET_DURATION = 1 # inform clients that they can retry nearly immediately
        IGNORED_PATHS = [
          %r{\A(/api/v3)?/rate_limit\z},
        ]

        def initialize(name = "internal-concurrent-authentication-fingerprint", ttl:, max:)
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
          return true if IGNORED_PATHS.any? { |path_regex| request.path_info =~ path_regex }

          false
        end

        protected

        def key(request)
          fingerprint(request, omit_ip: true)
        end
      end
    end
  end
end
