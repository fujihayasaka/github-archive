# typed: true
# frozen_string_literal: true

module GitHub
  module Middleware
    class Stats
      module Tracker
        class HTMLPipeline
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
            # An overwhelming number of requests do not run a warppipe pipeline, and we are most interested in _how_
            # many pipelines are run when they are run.
            pipeline_runs = GitHub::HTMLPipelineInstrumenter.pipeline_runs
            return unless pipeline_runs > 0

            tags = [
              tags_cache[TaggingHelper::CONTROLLER_TAG],
              tags_cache[TaggingHelper::ACTION_TAG],
              tags_cache[TaggingHelper::METHOD_TAG],
            ].compact

            dogstats.distribution("request.dist.html_pipeline_runs", pipeline_runs, tags: tags)
          end
        end
      end
    end
  end
end
