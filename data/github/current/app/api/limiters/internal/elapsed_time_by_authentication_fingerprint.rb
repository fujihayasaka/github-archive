# typed: true
# frozen_string_literal: true

module Api
  module Limiters
    module Internal
      class ElapsedTimeByAuthenticationFingerprint < GitHub::Limiters::MemcachedWindow
        include Api::Limiters::Internal::RateLimitModulator
        include Api::Limiters::TwirpHelpers
        include Api::Limiters::Helpers

        IGNORED_PATHS = [
          %r{\A(/api/v3)?/rate_limit\z},
        ]

        def initialize(name = "internal-time-based", max:)
          @max = max
          @request_start_key = "#{name}.elapsed.start"
          @request_cost_key = "#{name}.elapsed.cost"
          super(name, limit: max)
        end

        def ignored?(request)
          self.class.twirp_request?(request) ||
          IGNORED_PATHS.any? { |path_regex| request.path_info =~ path_regex }
        end

        def start(request)
          request.env[@request_start_key] = Time.now
          super
        end

        def record_finish(request)
          # (shawnHartsell 2025-01-22) this check is here to prevent nil errors if this method is caled
          # during a timeout for a request that is ignored. In these cases the requeired request.env variables
          # needs for the cost method will not have been set.
          return OK if ignored?(request)
          increment_counter(request)
        end

        protected

        def key(request)
          fingerprint(request, omit_ip: true)
        end

        def cost(request)
          return request.env[@request_cost_key] if request.env[@request_cost_key].present?

          request_started_at = T.cast(request.env[@request_start_key], Time)
          request_cost_in_sec = Time.now - request_started_at
          request.env[@request_cost_key] = Integer((request_cost_in_sec) * 1_000)
        end
      end
    end
  end
end
