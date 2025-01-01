# typed: true
# frozen_string_literal: true

module Api
  module Limiters
    class ElapsedTimeByAuthenticationFingerprint < GitHub::Limiters::MemcachedWindow
      include Api::Limiters::ObservabilityHelpers
      include Api::Limiters::TwirpHelpers
      include Api::Limiters::Helpers

      LIMITER_LOG_PREFIX = "elapsed".freeze
      REQUEST_START_KEY = "elapsed.start".freeze
      REQUEST_COST_KEY = "elapsed.cost".freeze

      IGNORED_PATHS = [
        %r{\A(/api/v3)?/rate_limit\z},
      ]

      def initialize(name = "time-based", max:)
        @max = max
        super(name, limit: max)
      end

      def ignored?(request)
        IGNORED_PATHS.any? { |path_regex| request.path_info =~ path_regex }
      end

      def start(request)
        request.env[REQUEST_START_KEY] = Time.now
        super
      end

      def record_finish(request)
        if self.class.twirp_request?(request)
          OK
        else
          current = increment_counter(request)

          if GitHub::Routers::Api.internal_api_host?(request.host) && GitHub.multi_tenant_enterprise?
            key = key(request)

            if (log_data = request.env[Rack::RequestLogger::APPLICATION_LOG_DATA])
              add_to_log_data(LIMITER_LOG_PREFIX, log_data, key, http_user_agent(request), cost(request), current, @max)
            end

            unless auth_type(request) == :other
              post_to_datadog(key, current, @max, kind: "elapsed")
            end
          end

          current
        end
      end

      protected

      def key(request)
        twirp_path = Api::Limiters::TwirpAuthenticationFingerprintByPath.twirp_path(request)

        if twirp_path
          client_name = Api::Internal::Twirp.client_name_from_header(request) || Api::Internal::Twirp::UNKNOWN_CLIENT_NAME
          "#{client_name}:#{fingerprint(request)}"
        else
          fingerprint(request)
        end
      end

      def cost(request)
        cost = request.env[REQUEST_COST_KEY]
        return cost if cost.present?

        request_started_at = T.cast(request.env[REQUEST_START_KEY], Time)
        request_cost_in_sec = Time.now - request_started_at
        request.env[REQUEST_COST_KEY] = Integer((request_cost_in_sec) * 1_000)
      end
    end
  end
end
