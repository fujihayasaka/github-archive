# typed: true
# frozen_string_literal: true

module GitHub
  module Middleware
    class Stats
      module Tracker
        class RepoAdvisories
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
            return unless stats[:controller] == "repos_advisories"

            tags = [
              tags_cache[TaggingHelper::STATUS_RANGE_TAG],
              tags_cache[TaggingHelper::CONTROLLER_TAG],
              tags_cache[TaggingHelper::ACTION_TAG],
              tags_cache[TaggingHelper::REPO_ADVISORY_SOURCE_TYPE_TAG],
            ].compact

            dogstats.distribution("request.repo_advisories_source_type.time", stats[:real_ms], tags: tags)
          end
        end
      end
    end
  end
end
