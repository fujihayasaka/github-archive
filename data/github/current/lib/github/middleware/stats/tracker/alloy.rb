# typed: true
# frozen_string_literal: true

module GitHub
  module Middleware
    class Stats
      module Tracker
        class Alloy
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
            return unless alloy_calls = stats[:alloy_calls]

            dogstats.distribution("request.alloy.calls", alloy_calls, tags: tags_cache.controller_action)
          end
        end
      end
    end
  end
end
