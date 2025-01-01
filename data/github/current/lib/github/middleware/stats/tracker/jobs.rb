# typed: true
# frozen_string_literal: true

module GitHub
  module Middleware
    class Stats
      module Tracker
        class Jobs
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
            return unless self.track_job_stats?

            dogstats.distribution("request.dist.jobs_enqueued", self.job_stats)
          end

          def self.track_job_stats?
            defined?(GitHub::JobStats)
          end

          def self.job_stats
            GitHub::JobStats.enqueued.values.sum
          end
        end
      end
    end
  end
end
