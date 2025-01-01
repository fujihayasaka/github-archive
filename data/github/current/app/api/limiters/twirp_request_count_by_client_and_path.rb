# typed: true
# frozen_string_literal: true

# This limiter tracks the request counts made per Twirp client and hashed endpoint over
# a 60-second window, with a threshold of 10k requests.
#
# This is intended to replace the `Api::Limiters::TwirpAuthenticationFingerprintByPath`
# rule once we have this tuned to the right degree for internal usage.
#
module Api
  module Limiters
    class TwirpRequestCountByClientAndPath < GitHub::Limiters::MemcachedWindow
      include Api::Limiters::TwirpHelpers
      include Api::Limiters::TwirpObservabilityHelpers

      # Custom limits for specific clients and paths that need to be rate-limited differently from the default.
      # The paths used are matched against the full path of the request using Api::Internal::Twirp::PATH_REGEX.
      #
      # Before adding to this list, please consult with the API Platform team.
      #
      # IMPORTANT: The values here are based on dotcom production data and are subject to change. They are
      # also based on the maximum value of the default limit; if the default limit changes, these values must also be updated.
      CUSTOM_CLIENT_PATH_THRESHOLDS = T.let({
        # see: https://github.com/github/api-platform/issues/6183#issuecomment-2403501401
        "package_registry" => {
          "registrymetadata.core.v1.LoginAPI/ValidateTokenScopes" => 400_000,
        },
        # see: https://github.com/github/api-platform/issues/6232#issuecomment-2475040570
        "actions_broker_listener" => {
          "features.core.v1.FeaturesAPI/CheckActorFeatures" => 500_000
        },
        # see https://github.com/github/api-platform/issues/6321
        "copilot_api" => {
          "features.core.v1.FeaturesAPI/CheckActorFeatures" => 400_000,
          "copilot.users.v1.CopilotUserDetailAPI/GetCopilotUser" => 175_000
        }
      }, T::Hash[String, T::Hash[String, Integer]])

      LOG_DATA_PREFIX = "gh.api.twirp.req_count_path_limiter."

      def initialize(max:)
        self.max_limit = max
        super("twirp-request-count-by-client-and-path", limit: max)
      end

      attr_accessor :max_limit
      private :max_limit=

      def start(request)
        return OK unless self.class.twirp_request_count_by_client_and_path_enabled?(request)
        set_custom_limit(request)
        super(request)
      end

      def record_finish(request)
        return OK unless self.class.twirp_request_count_by_client_and_path_enabled?(request)

        cur_limit = increment_counter(request)
        client = self.class.twirp_client_name_per_request(request)

        if (log_data = request.env[Rack::RequestLogger::APPLICATION_LOG_DATA])
          log_data["#{LOG_DATA_PREFIX}client_name"] = client
          log_data["#{LOG_DATA_PREFIX}current"] = cur_limit
          log_data["#{LOG_DATA_PREFIX}max"] = @limit
        end

        post_count_limiter_to_datadog(client, cur_limit, @limit, evaluation: true)
      end

      # If the request was canceled we don't want to cost the request.
      def cancel(request)
        OK
      end

      protected

      def set_custom_limit(request)
        # limiters are a singleton, so we need to reset the limit instance variable for each request
        @limit = self.max_limit

        client_name = self.class.twirp_client_name_per_request(request)

        custom_limit_larger_than_default = false
        custom_limit_set = false

        rpc_path = self.class.twirp_rpc_path(request)

        if rpc_path&.present?
          custom_limit = CUSTOM_CLIENT_PATH_THRESHOLDS.dig(client_name, rpc_path)

          if custom_limit&. > @limit
            custom_limit_set = true
            custom_limit_larger_than_default = true
            @limit = custom_limit
          end
        end

        if (log_data = request.env[Rack::RequestLogger::APPLICATION_LOG_DATA])
          log_data["#{LOG_DATA_PREFIX}rpc_path"] = rpc_path
          log_data["#{LOG_DATA_PREFIX}custom_limit_set_larger_than_default"] = custom_limit_larger_than_default
          log_data["#{LOG_DATA_PREFIX}custom_limit_set"] = custom_limit_set
        end
      end

      # Protected: The key is composed of the client name and the hashed path.
      def key(request)
        hashed_path = Digest::SHA256.hexdigest(request.path_info)
        client_name = self.class.twirp_client_name_per_request(request)
        "#{client_name}:#{hashed_path}"
      end
    end
  end
end
