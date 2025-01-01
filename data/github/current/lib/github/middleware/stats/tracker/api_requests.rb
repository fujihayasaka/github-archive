# typed: true
# frozen_string_literal: true

module GitHub
  module Middleware
    class Stats
      module Tracker
        class ApiRequests
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
            return if stats[:request_category] != TaggingHelper::API_TAG

            tags = [
              tags_cache[TaggingHelper::INTERNAL_API_TAG],
              tags_cache[TaggingHelper::GRAPHQL_API_TAG],
              tags_cache[TaggingHelper::CATALOG_SERVICE_TAG],
            ].compact

            status = stats[:response_status]
            tags << if !status.instance_of?(Integer)
              "availability:unknown"
            elsif status < 500
              "availability:success"
            else
              "availability:unhandled_error"
            end

            if stats[:graphql_api_request]
              TaggingHelper.add_tag_unless_nil(tags, TaggingHelper::RESPONSE_LT6000_TAG, stats[:real_ms] < 6000.0)
            else
              TaggingHelper.add_tag_unless_nil(tags, TaggingHelper::RESPONSE_LT3000_TAG, stats[:real_ms] < 3000.0)
            end

            dogstats.distribution("api.request", stats[:real_ms], tags: tags)
          end
        end
      end
    end
  end
end
