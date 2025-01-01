# typed: true
# frozen_string_literal: true

module GitHub
  module Middleware
    class Stats
      module Tracker
        class QueueingTiming
          extend T::Sig
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
            return unless queue_time = env[TaggingHelper::REQ_WAIT_TIME]

            queue_ms = queue_time * 1_000
            dogstats.distribution("request.queued.time", queue_ms)
            dogstats.distribution("request.pod.queued.time", queue_ms, tags: tags_cache.pod_name)
          end
        end
      end
    end
  end
end
