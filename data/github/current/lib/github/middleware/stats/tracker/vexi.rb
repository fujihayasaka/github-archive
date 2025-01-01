# typed: true
# frozen_string_literal: true

module GitHub
  module Middleware
    class Stats
      module Tracker
        class Vexi
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
            tags = [tags_cache[TaggingHelper::CONTROLLER_TAG]].compact

            # Prevent division by zero errors
            return if stats.fetch(:real_ms, 0) == 0

            # Percentage overhead spent on feature flags
            dogstats.distribution("request.dist.vexi_overhead.percent", ((VexiSubscriber.total_enabled_duration + VexiSubscriber.total_preload_duration) * 1000) / stats[:real_ms] * 100, tags: tags)
          end
        end
      end
    end
  end
end
