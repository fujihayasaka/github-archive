# typed: true
# frozen_string_literal: true

module Api
  module Limiters
    # RequestsByPersonalAccessToken is a secondary (unauthenticated) rate limiter which
    # limits requests by token while ignoring IP address. Moreover, it is only applied
    # to requests authenticating with FG PATs/PATs v2.
    #
    # Context https://github.com/github/availability/issues/2933
    class RequestsByPersonalAccessToken < GitHub::Limiters::MemcachedWindow
      include Api::Limiters::TwirpHelpers

      TOKEN_ONLY_FINGERPRINT = "github.authentication_fingerprint_token_only".freeze

      def initialize(name = "global-request-by-pat", max:)
        super(name, limit: max)
      end

      def ignored?(request)
        # this limiter only applies to requests authenticated with PATs v2
        !calculate_fingerprint(request.env).personal_access_token?
      end

      def start(request)
        if at_limit?(request)
          GitHub.dogstats.increment("limiters.global_request_by_pat.exceeded")

          return State.new limited: true, duration: duration, glb: @glb
        end

        record_start(request)
        OK
      end

      def record_start(request)
        increment_counter(request)
      end

      protected

      def fingerprint(request)
        calculate_fingerprint(request.env).to_s
      end

      # should only be calculated once for each request
      def calculate_fingerprint(env)
        # we can't use the memoization present in the Api::Middleware::RequestAuthenticationFingerprint
        # because the fingerprint includes the client IP
        env[TOKEN_ONLY_FINGERPRINT] ||= Api::RequestAuthenticationFingerprint.from(env, token_serialization: :hashed_token)
      end

      def key(request)
        fingerprint(request)
      end
    end
  end
end
