# typed: true
# frozen_string_literal: true

module GitHub
  module Middleware
    class Stats
      module Tracker
        extend T::Sig
        extend T::Helpers
        interface!

        sig do
          abstract.params(
            dogstats: T.untyped,
            env: T.untyped,
            stats: T::Hash[Symbol, T.untyped],
            tags_cache: GitHub::DatadogTagsCache,
          ).void
        end
        def track(dogstats, env, stats, tags_cache); end
      end
    end
  end
end
