# typed: true
# frozen_string_literal: true

module GitHub
  module Middleware
    class Stats
      module Tracker
        class Flipper
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

            # Total time spend calculating flipper gates
            dogstats.distribution("request.dist.flipper_total_time", FlipperSubscriber.total_enabled_duration + FlipperSubscriber.total_preload_duration, tags: tags)

            # Percentage overhead spent on feature flags
            dogstats.distribution("request.dist.flipper_overhead.percent", ((FlipperSubscriber.total_enabled_duration + FlipperSubscriber.total_preload_duration) * 1000) / stats[:real_ms] * 100, tags: tags)
          end
        end
      end
    end
  end
end
