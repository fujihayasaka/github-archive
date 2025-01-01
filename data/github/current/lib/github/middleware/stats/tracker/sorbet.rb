# typed: true
# frozen_string_literal: true

module GitHub
  module Middleware
    class Stats
      module Tracker
        class Sorbet
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
            dogstats.distribution("request.type_checking.time", stats[:real_ms]) if GitHub::Sorbet::Runtime.reporting_errors?
          end
        end
      end
    end
  end
end
