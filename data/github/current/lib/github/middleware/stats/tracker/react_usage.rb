# typed: true
# frozen_string_literal: true

module GitHub
  module Middleware
    class Stats
      module Tracker
        class ReactUsage
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
            react_tag = TaggingHelper.react_type(env)
            return if react_tag == TaggingHelper::UNKNOWN

            tags = tags_cache.controller_action.dup
            TaggingHelper.add_tag_unless_nil(tags, TaggingHelper::REACT_TYPE_TAG, react_tag)
            tags << tags_cache[TaggingHelper::STATUS_RANGE_TAG]
            tags << "#{TaggingHelper::IS_REACT_TAG}:true" if react_tag != "rails"
            tags << tags_cache[TaggingHelper::STAFF_TAG]

            dogstats.distribution("react.request.duration", stats[:real_ms], tags: tags)
          end
        end
      end
    end
  end
end
