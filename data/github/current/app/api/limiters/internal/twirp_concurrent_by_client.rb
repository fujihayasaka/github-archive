# typed: true
# frozen_string_literal: true

# This limiter tracks the concurrent Twirp API requests associated with a specific Twirp client,
# keyed by the client name from the HMAC header, allowing per-service concurrent request limits for internal Twirp clients.
module Api
  module Limiters
    module Internal
      class TwirpConcurrentByClient < GitHub::Limiters::MemcachedWindow
        include Api::Limiters::TwirpHelpers

        # Per-client overrides sourced from github/api-platform#9010.
        # All other clients use the configured default maximum.
        TWIRP_CLIENT_CUSTOM_THRESHOLDS = T.let({
          "launch"                  => 1100,
          "copilot_api"             =>  900,
          "copilot_mission_control" =>  900,
          "actions_results"         =>  900,
          "package_registry"        =>  900,
        }.freeze, T::Hash[String, Integer])

        RESET_DURATION = 1 # inform clients that they can retry nearly immediately

        def initialize(max: GitHub.internal_twirp_concurrent_by_client_max)
          @default_limit = max
          super("twirp-concurrent-by-client", limit: @default_limit)
        end

        def ignored?(request)
          !self.class.twirp_request?(request) ||
            !FeatureFlag.vexi.enabled?(:twirp_concurrent_by_client_enabled, default: false)
        end

        def start(request)
          set_custom_limit(request)
          super(request)
        end

        def record_start(request)
          increment_counter(request)
        end

        def record_finish(request)
          current_total = decrement_counter(request)
          return unless current_total

          client = self.class.twirp_client_name_per_request(request)
          maximum_value = @limit

          post_to_datadog(client, current_total, maximum_value)
        end

        def duration
          RESET_DURATION
        end

        protected

        def set_custom_limit(request)
          client_name = self.class.twirp_client_name_per_request(request)
          @limit = TWIRP_CLIENT_CUSTOM_THRESHOLDS[client_name] || @default_limit
        end

        # Protected: The key is composed of the client name only
        def key(request)
          self.class.twirp_client_name_per_request(request)
        end

        private

        def post_to_datadog(client, current, max)
          return unless FeatureFlag.vexi.enabled?(:twirp_concurrent_by_client_post_to_datadog, default: false)

          percentage = current / max.to_f
          tags = ["key:#{client}", "kind:concurrent", "limiter:#{name}"]

          GitHub.dogstats.gauge("api.limiter.gauge.current", current, tags: tags)
          GitHub.dogstats.gauge("api.limiter.gauge.percent", percentage, tags: tags)
        end
      end
    end
  end
end
