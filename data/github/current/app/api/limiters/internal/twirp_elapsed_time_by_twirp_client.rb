# typed: true
# frozen_string_literal: true

# This limiter tracks the Twirp API compute associated with a specific Twirp client across all IP addresses, unlike
# the previous implementation which used the IP address for a rate-limiting key. This helped to skew usage patterns
# and favoured services which spanned dozens of IP addresses.
#
# This is a pattern we want to discourage as the limiter may now span multiple stamps
module Api
  module Limiters
    module Internal
      class TwirpElapsedTimeByTwirpClient < GitHub::Limiters::MemcachedWindow
        include Api::Limiters::TwirpHelpers
        include Api::Limiters::ObservabilityHelpers

        DEFAULT_MAXIMUM = T.let(500_000, Integer) # milliseconds per minute

        TWIRP_CLIENT_CUSTOM_THRESHOLDS = T.let({
          "copilot_api" => 16_000_000,
          "launch" => 20_000_000,
          "actions_broker_listener" => 15_000_000,
          "package_registry" => 10_000_000,
          "octoshift" => 8_000_000,
          "token_scanning_service" => 7_000_000,
          "actions_results" => 3_000_000,
          "notifyd" => 2_000_000,
          "auditlog" => 1_500_000,
          "turboghas" => 1_300_000,
          "billing" => 700_000,
        }, T::Hash[String, Integer])

        IGNORED_PATHS = [
          %r{\A(/api/v3)?/rate_limit\z},
        ]

        LOG_DATA_PREFIX = "twirp.elapsed_time".freeze
        REQUEST_START_KEY = "twirp.elapsed_time.start".freeze
        REQUEST_COST_KEY = "twirp.elapsed_time.cost".freeze

        def initialize
          super("twirp-elapsed-time-by-twirp-client", limit: DEFAULT_MAXIMUM)
        end

        def ignored?(request)
          IGNORED_PATHS.any? { |path_regex| request.path_info =~ path_regex } || !self.class.twirp_request?(request)
        end

        def start(request)
          request.env[REQUEST_START_KEY] = Time.now
          set_custom_limit(request)
          super(request)
        end

        def record_finish(request)
          # (shawnHartsell 2024-11-22) HERE BE DRAGONS
          # This check is here from preventing this method from executing during timeouts for requests it is set to ignore.
          # This is required because the timeout middleware will call record_finish on all limiters and does not currenly
          # take into account the ignored status of a limiter.
          #
          # If this check is removed, exceptions will be thrown as the required env variables for calculating cost will not be have
          # been set (via the start method)
          return OK if ignored?(request)

          increment_counter(request)

          client = self.class.twirp_client_name_per_request(request)
          current_total = val(key(request))
          maximum_value = @limit

          if (log_data = request.env[Rack::RequestLogger::APPLICATION_LOG_DATA])
            add_to_log_data(LOG_DATA_PREFIX, log_data, key(request), client, cost(request), current_total, maximum_value)
          end

          post_to_datadog(client, current_total, maximum_value, kind: "elapsed")
        end

        # If the request was canceled we don't want to cost the request.
        def cancel(request)
          OK
        end

        protected

        def set_custom_limit(request)
          client_name = self.class.twirp_client_name_per_request(request)
          @limit = TWIRP_CLIENT_CUSTOM_THRESHOLDS[client_name] || DEFAULT_MAXIMUM
        end

        # Protected: The key is composed of the client name only
        def key(request)
          self.class.twirp_client_name_per_request(request)
        end

        def cost(request)
          cost = request.env[REQUEST_COST_KEY]

          return cost if cost.present?

          # The cost should be the number of milliseconds this request has taken
          cost = Integer((Time.now - T.cast(request.env[REQUEST_START_KEY], Time)) * 1_000)

          request.env[REQUEST_COST_KEY] = cost
        end
      end
    end
  end
end
