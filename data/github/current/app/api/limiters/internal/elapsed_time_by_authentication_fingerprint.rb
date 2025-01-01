# typed: true
# frozen_string_literal: true

module Api
  module Limiters
    module Internal
      class ElapsedTimeByAuthenticationFingerprint < Api::Limiters::ElapsedTimeByAuthenticationFingerprint
        LIMITER_LOG_PREFIX = "internal.elapsed"
        def initialize(max:)
          @max = max
          super("internal-time-based", max: max)
        end

        def record_finish(request)
          current = increment_counter(request)
          key = key(request)

          if (log_data = request.env[Rack::RequestLogger::APPLICATION_LOG_DATA])
            add_to_log_data(LIMITER_LOG_PREFIX, log_data, key, http_user_agent(request), cost(request), current, @max)
          end

          unless auth_type(request, omit_ip: true) == :other
            post_to_datadog(key, current, @max, kind: "elapsed", evaluation: true)
          end
        end

        def ignored?(request)
          return true unless GitHub.flipper[:internal_elapsed_time_by_authentication_fingerprint].enabled?
          return true unless GitHub::Routers::Api.internal_api_host?(request.host)
          return true if self.class.twirp_request?(request)
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
