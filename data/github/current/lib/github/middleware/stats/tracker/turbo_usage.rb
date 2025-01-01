# typed: true
# frozen_string_literal: true

module GitHub
  module Middleware
    class Stats
      module Tracker
        class TurboUsage
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
            turbo_tag = TaggingHelper.turbo(env)
            return if turbo_tag == TaggingHelper::UNKNOWN

            tags = tags_cache.controller_action.dup
            TaggingHelper.add_tag_unless_nil(tags, TaggingHelper::TURBO_TYPE_TAG, turbo_tag)

            dogstats.distribution("turbo.request", stats[:real_ms], tags: tags)
          end
        end
      end
    end
  end
end
