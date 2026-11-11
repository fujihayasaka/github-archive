# typed: true
# frozen_string_literal: true

module GitHub
  module Middleware
    class Stats
      module Tracker
        class SlowRequests
          extend Tracker

          sig do
            override.params(
              dogstats: T.untyped,
              env: T.untyped,
              stats: T::Hash[Symbol, T.untyped],
              tags_cache: GitHub::DatadogTagsCache,
            ).void
          end
          def self.track(dogstats, env, stats, tags_cache)
            return unless stats[:real_ms] / 1000.0 > GitHub.slow_request_threshold

            tags = [
              tags_cache[TaggingHelper::CATEGORY_TAG],
              tags_cache[TaggingHelper::CONTROLLER_TAG],
              tags_cache[TaggingHelper::ACTION_TAG],
            ].compact

            dogstats.increment("request.slow", tags: tags)
          end
        end
      end
    end
  end
end
