# typed: true
# frozen_string_literal: true

module GitHub
  module Middleware
    class Stats
      module Tracker
        class KubePodTiming
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
            # this metric is used to track average response time by pod. please don't add any tags to it to
            # avoid cardinality problems
            dogstats.distribution("request.pod.time", stats[:real_ms], tags: tags_cache.pod_name)
          end
        end
      end
    end
  end
end
