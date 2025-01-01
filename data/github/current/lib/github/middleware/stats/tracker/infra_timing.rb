# typed: true
# frozen_string_literal: true

module GitHub
  module Middleware
    class Stats
      module Tracker
        class InfraTiming
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
            # request.infra.* metrics have no application specific tags, but will have infrastructure specific tags
            # configured, so that we can measure request timing per kube cluster, host, hardware type, etc.
            dogstats.distribution("request.infra.time", stats[:real_ms])
            dogstats.distribution("request.infra.cpu_time", stats[:cpu_ms])
            dogstats.distribution("request.infra.idle_time", stats[:idle_ms])
            dogstats.distribution("request.infra.cpu_throttle_time_ms", stats[:cpu_throttle_time_ms])
          end
        end
      end
    end
  end
end
