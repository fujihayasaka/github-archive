# typed: true
# frozen_string_literal: true

module GitHub
  module Middleware
    class Stats
      module Tracker
        class RequestReferrer
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
            return if stats[:request_category] != "ajax"

            action_suffix = self.is_react_referrer?(env) ? "_react" : ""
            request_dist_referrer_tags = TaggingHelper.calculate_referrer(env, action_suffix:)
            request_dist_referrer_tags << tags_cache[TaggingHelper::CONTROLLER_TAG]
            request_dist_referrer_tags << tags_cache[TaggingHelper::ACTION_TAG]

            dogstats.distribution("request.dist.referrer", stats[:real_ms], tags: request_dist_referrer_tags)
          end

          def self.is_react_referrer?(env)
            env["HTTP_GITHUB_IS_REACT"] == "true"
          end
        end
      end
    end
  end
end
