# typed: true
# frozen_string_literal: true

module GitHub
  module Middleware
    class Stats
      module Tracker
        class GlbToUnicornTiming
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
            return unless glb_wait_time = env[TaggingHelper::GLB_WAIT_TIME]

            glb_wait_ms = glb_wait_time * 1_000
            dogstats.distribution("request.glb_to_unicorn.time", glb_wait_ms)
            dogstats.distribution("request.pod.glb_to_unicorn.time", glb_wait_ms, tags: tags_cache.pod_name)
          end
        end
      end
    end
  end
end
