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
    module Internal
      class TwirpRequestCountByClientAndPath < GitHub::Limiters::MemcachedWindow
        include Api::Limiters::TwirpHelpers
        include Api::Limiters::ObservabilityHelpers
        include Api::Limiters::Internal::RateLimitModulator

        DEFAULT_MAXIMUM = T.let(100_000, Integer)

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
          # see: https://github.com/github/api-platform/issues/6247
          "actions_broker_listener" => {
            "features.core.v1.FeaturesAPI/CheckActorFeatures" => 500_000
          },
          # see https://github.com/github/api-platform/issues/6321
          "copilot_api" => {
            "features.core.v1.FeaturesAPI/CheckActorFeatures" => 400_000,
            "copilot.users.v1.CopilotUserDetailAPI/GetCopilotUser" => 175_000
          },
          "launch" => {
            "actions.core.v1.ResolveActionsAPI/ResolveActions" => 400_000
          }
        }, T::Hash[String, T::Hash[String, Integer]])

        LOG_DATA_PREFIX = "twirp.req_count_path_limiter"

        # IMPORTANT: The default max for TwirpRequestCountByClientAndPath affects custom thresholds for specific clients and paths.
        # If you change this value, you must also update the custom thresholds in the limiter.
        def initialize
          super("twirp-request-count-by-client-and-path", limit: DEFAULT_MAXIMUM)
        end

        def ignored?(request)
          !self.class.twirp_request?(request)
        end

        def start(request)
          set_custom_limit(request)
          super(request)
        end

        def record_finish(request)
          current_total = increment_counter(request)
          client = self.class.twirp_client_name_per_request(request)

          # the key() includes the hashed path, so set the key to the client name to keep cardinality low
          post_to_datadog(client, current_total, @limit, kind: "count_v2", evaluation: false)
        end

        # If the request was canceled we don't want to cost the request.
        def cancel(request)
          OK
        end

        protected

        def set_custom_limit(request)
          client_name = self.class.twirp_client_name_per_request(request)
          rpc_path = self.class.twirp_rpc_path(request)
          @limit = CUSTOM_CLIENT_PATH_THRESHOLDS.dig(client_name, rpc_path) || DEFAULT_MAXIMUM
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
end
