# typed: true
# frozen_string_literal: true

module GitHub
  module Middleware
    class Stats
      module Tracker
        class MetricCount
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
            return unless dogstats.respond_to?(:metrics_counts)
            return unless defined?(GitHub.flipper) && GitHub.flipper[:metrics_details_metric].enabled?

            tags = [
              tags_cache[TaggingHelper::METHOD_TAG],
              tags_cache[TaggingHelper::CONTROLLER_TAG],
              tags_cache[TaggingHelper::ACTION_TAG],
            ].compact

            dogstats.metrics_counts.clone.each do |metric_name, count|
              details_tags = tags.dup
              details_tags << "metric_name:#{metric_name}"
              dogstats.distribution("request.dist.metrics_details", count, tags: details_tags)
            end
          end
        end
      end
    end
  end
end
