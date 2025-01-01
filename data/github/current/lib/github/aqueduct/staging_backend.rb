# typed: true
# frozen_string_literal: true

require "aqueduct"
require "forwardable"
require "resqued/queue_subset_selector"
require_relative "queue_strategy_backend"

module GitHub
  module Aqueduct
    # StagingBackend is a backend for staging environments that uses the Aqueduct::Worker::AqueductBackend
    # for job processing. We use GitHub::Aqueduct::QueueStrategyBackend as the base, giving us strategy composition at
    # initialization time.
    #
    # Example usage:
    # staging_backend = GitHub::Aqueduct::StagingBackend.new(
    #     backend: ::Aqueduct::Worker::AqueductBackend.new(client: aqueduct_staging),
    #     queue_strategies: [
    #       GitHub::Aqueduct::QueueStrategies::QueuePrioritization.new(prioritize_by: prioritize_by),
    #       GitHub::Aqueduct::QueueStrategies::QueueSubsetSelection.new(
    #         queue_subset_selector: queue_subset_selector,
    #         prioritize_by: prioritize_by
    #       ),
    #     ]
    #   )
    #
    # The StagingBackend points to our Aqueduct Staging cluster and should be only used by the Data Pipelines team.
    # At the moment, if we dont want the worker pool to point to the aqueduct staging cluster, we can set the
    # feature flag aqueduct_staging_backend_enabled to false and it will do no-ops.
    class StagingBackend < QueueStrategyBackend

      def pop(queues, timeout, tags: {}, worker_id:, worker_pool: nil, worker_idle_ms: 0)
        if aqueduct_staging_enabled?
          super(queues, timeout, tags: tags, worker_id: worker_id, worker_pool: worker_pool, worker_idle_ms: worker_idle_ms)
        else
          # If aqueduct staging is not enabled, we just sleep for backoff_seconds seconds simulating a backoff
          # We dont hammer feature flag checks in the aqueduct staging backend while respecting the backoff logic.
          # At the moment it is 60 seconds as it is a reasonable time for a dev to do the change and see the effect.
          time_sleep_in_seconds = 60
          ::Aqueduct::Worker::Result.empty(backend_name: "staging", backoff_seconds: time_sleep_in_seconds)
        end
      end

      def aqueduct_staging_enabled?
        FeatureFlag.vexi.enabled?("aqueduct_staging_backend_enabled", default: false)
      end
    end
  end
end
