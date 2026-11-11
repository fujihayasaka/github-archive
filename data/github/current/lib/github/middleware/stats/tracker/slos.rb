# typed: true
# frozen_string_literal: true

module GitHub
  module Middleware
    class Stats
      module Tracker
        class Slos
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
            TaggingHelper.tracked_latency_slos(env).each do |name, target|
              success = stats[:real_ms] < target
              # Any character in the service name that's not alphanumeric, a period or underscore will be converted to an underscore
              # Example: The metric for the "github/code_scanning" catalog service will appear as "github_code_scanning.slo" in Datadog
              dogstats.increment("#{stats[:catalog_service]}.slo", tags: ["#{TaggingHelper::SUCCESS_TAG}:#{success}", "#{TaggingHelper::NAME_TAG}:latency/#{name}"])
            end

            TaggingHelper.tracked_availability_slos(env).each do |name|
              status = stats[:response_status]
              success = status != TaggingHelper::UNKNOWN && status < 500
              dogstats.increment("#{stats[:catalog_service]}.slo", tags: ["#{TaggingHelper::SUCCESS_TAG}:#{success}", "#{TaggingHelper::NAME_TAG}:availability/#{name}"])
            end
          end
        end
      end
    end
  end
end
