# typed: true
# frozen_string_literal: true

module GitHub
  module Middleware
    class Stats
      module Tracker
        class HtmlRequests
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
            request_formats = env["action_dispatch.request.formats"]
            return unless request_formats&.any? { |format| format&.symbol == :html }

            tags = tags_cache.controller_action_service_method_status_category.dup
            TaggingHelper.add_tag_unless_nil(tags, TaggingHelper::LOGGED_IN_TAG, stats[:logged_in]) if stats[:logged_in] != TaggingHelper::UNKNOWN

            dogstats.distribution("request.html.time", stats[:real_ms], tags: tags)
          end
        end
      end
    end
  end
end
