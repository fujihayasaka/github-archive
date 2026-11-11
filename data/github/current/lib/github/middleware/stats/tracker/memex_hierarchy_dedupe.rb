# typed: true
# frozen_string_literal: true

module GitHub
  module Middleware
    class Stats
      module Tracker
        class MemexHierarchyDedupe
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
            result = TaggingHelper.hierarchy_dedupe_result(env)
            return unless result

            filter = TaggingHelper.hierarchy_dedupe_filter(env)

            tags = tags_cache.controller_action.dup
            TaggingHelper.add_tag_unless_nil(tags, TaggingHelper::HIERARCHY_DEDUPE_RESULT_TAG, result)
            TaggingHelper.add_tag_unless_nil(tags, TaggingHelper::HIERARCHY_DEDUPE_FILTER_TAG, filter)

            dogstats.distribution("memex.hierarchy_dedupe.request_time", stats[:real_ms], tags: tags)
          end
        end
      end
    end
  end
end
