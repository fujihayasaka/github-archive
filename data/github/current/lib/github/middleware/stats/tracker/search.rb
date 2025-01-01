# typed: true
# frozen_string_literal: true

module GitHub
  module Middleware
    class Stats
      module Tracker
        class Search
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
            return unless search_class = env[GitHub::TaggingHelper::SEARCH_QUERY_CLASS]

            tags = tags_cache.controller_action.dup
            TaggingHelper.add_tag_unless_nil(tags, TaggingHelper::SEARCH_QUERY_CLASS_TAG, search_class)

            dogstats.distribution("search.request", stats[:real_ms], tags: tags)
          end
        end
      end
    end
  end
end
