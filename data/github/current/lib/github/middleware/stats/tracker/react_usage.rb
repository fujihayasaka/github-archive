# typed: true
# frozen_string_literal: true

module GitHub
  module Middleware
    class Stats
      module Tracker
        class ReactUsage
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
            react_tag = TaggingHelper.react_type(env)
            return if react_tag == TaggingHelper::UNKNOWN

            staff_user = TaggingHelper.staff_user(env)
            tags = tags_cache.controller_action.dup
            TaggingHelper.add_tag_unless_nil(tags, TaggingHelper::REACT_TYPE_TAG, react_tag)
            TaggingHelper.add_tag_unless_nil(tags, TaggingHelper::STAFF_TAG, staff_user)
            tags << tags_cache[TaggingHelper::STATUS_RANGE_TAG]

            dogstats.distribution("react.request.duration", stats[:real_ms], tags: tags)
          end
        end
      end
    end
  end
end
