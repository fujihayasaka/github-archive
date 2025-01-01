# typed: true
# frozen_string_literal: true

module Api
  module Limiters
    module Internal
      class ConcurrentAuthenticationFingerprint < Api::Limiters::ConcurrentAuthenticationFingerprint
        LIMITER_LOG_PREFIX = "internal.concurrent"
        def initialize(ttl:, max:)
          @max = max
          super("internal-concurrent-authentication-fingerprint", ttl: ttl, max: max)
        end

        def record_start(request)
          current = increment_counter(request)
          key = key(request)

          if (log_data = request.env[Rack::RequestLogger::APPLICATION_LOG_DATA])
            add_to_log_data(LIMITER_LOG_PREFIX, log_data, key, http_user_agent(request), nil, current, @max)
          end

          unless auth_type(request, omit_ip: true) == :other
            post_to_datadog(key, current, @max, kind: "concurrent", evaluation: true)
          end
        end

        def ignored?(request)
          return true unless GitHub.flipper[:internal_concurrent_authentication_fingerprint].enabled?
          return true unless GitHub::Routers::Api.internal_api_host?(request.host)
          return true if super(request)

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
