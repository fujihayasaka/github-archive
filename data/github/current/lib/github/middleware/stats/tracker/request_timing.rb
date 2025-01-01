# typed: true
# frozen_string_literal: true

module GitHub
  module Middleware
    class Stats
      module Tracker
        class RequestTiming
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
            tags = tags_cache.controller_action_service_method_status_category

            request_dist_tags = tags.dup
            request_dist_tags << tags_cache[TaggingHelper::STATUS_TAG]
            TaggingHelper.add_tag_unless_nil(request_dist_tags, TaggingHelper::RAILS_VERSION_TAG, TaggingHelper.rails_version)
            TaggingHelper.add_tag_unless_nil(request_dist_tags, TaggingHelper::PJAX_TAG, stats[:pjax]) if stats[:pjax] != TaggingHelper::UNKNOWN
            TaggingHelper.add_tag_unless_nil(request_dist_tags, TaggingHelper::LOGGED_IN_TAG, stats[:logged_in]) if stats[:logged_in] != TaggingHelper::UNKNOWN
            TaggingHelper.add_tag_unless_nil(request_dist_tags, TaggingHelper::STAFF_TAG, stats[:is_staff]) if stats[:is_staff] != TaggingHelper::UNKNOWN
            request_dist_tags << tags_cache[TaggingHelper::GRAPHQL_API_TAG]
            TaggingHelper.add_tag_unless_nil(request_dist_tags, TaggingHelper::CODESPACES_AUTOMATED_TESTING_TAG, stats[:codespaces_automated_testing]) if stats[:codespaces_automated_testing]
            request_dist_tags << tags_cache[TaggingHelper::INTERNAL_API_TAG] if !stats[:graphql_api_request]
            TaggingHelper.add_tag_unless_nil(request_dist_tags, TaggingHelper::GRAPHQL_OPERATION_TYPE, stats[:graphql_operation_type]) if stats[:graphql_api_request]
            request_dist_tags.compact!

            dogstats.distribution("request.dist.time", stats[:real_ms], tags: request_dist_tags)
            dogstats.distribution("request.dist.cpu_time", stats[:cpu_ms], tags: tags)
            dogstats.distribution("request.dist.cpu_thread_time", stats[:cpu_thread_ms], tags: tags)
            dogstats.distribution("request.dist.idle_time", stats[:idle_ms], tags: tags)
          end
        end
      end
    end
  end
end
