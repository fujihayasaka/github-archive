# typed: true
# frozen_string_literal: true

module GitHub
  module Middleware
    class Stats
      module Tracker
        class RequestReferrer
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

            request_dist_referrer_tags = tags_cache.controller_action_react_logged_in_staff.dup
            request_dist_referrer_tags += TaggingHelper.calculate_referrer(env)
            is_react = self.is_react_referrer?(env)
            request_dist_referrer_tags << [TaggingHelper::IS_REACT_TAG, is_react].join(":") if is_react
            request_dist_referrer_tags.compact!

            dogstats.distribution("request.dist.referrer_cpu", stats[:cpu_ms], tags: request_dist_referrer_tags)
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
