# typed: true
# frozen_string_literal: true

module GitHub
  module Middleware
    class Stats
      module Tracker
        class ProfileType
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
            return unless %w[profiles org_repositories].include?(stats[:controller])

            tags = [
              tags_cache[TaggingHelper::LOGGED_IN_TAG],
              tags_cache[TaggingHelper::STATUS_RANGE_TAG],
              tags_cache[TaggingHelper::CONTROLLER_TAG],
              tags_cache[TaggingHelper::ACTION_TAG],
              tags_cache[TaggingHelper::PROFILE_TYPE],
            ].compact

            dogstats.distribution("request.profile_type.time", stats[:real_ms], tags: tags)
          end
        end
      end
    end
  end
end
