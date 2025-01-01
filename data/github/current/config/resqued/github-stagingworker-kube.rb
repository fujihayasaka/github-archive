# typed: true
# frozen_string_literal: true

# Configuration for the Aqueduct Staging worker pool deployment in Kubernetes. Loads after github-environment.rb.

require "resqued/metrics_server"
require "resqued/worker_readiness"

GitHub.role = :stagingworker
Aqueduct::Worker.configure do |config|
  config.worker_pool = "github-stagingworker-kube"
end

# Provide aqueduct.workers.count metrics
T.unsafe(self).before_fork { Resqued::MetricsServer.start }

# Drop a file on disk to indicate that the workers are ready.
T.unsafe(self).after_fork { |_worker| Resqued::WorkerReadiness.report_ready }

prioritize_by = Resqued::ShouldStartWithinPriority.new(buckets: %w[30m 2h])
queue_subset_selector = Resqued::QueueSubsetSelector.new(
  queue_subset_size: ENV.fetch("RESQUED_QUEUE_SUBSET_SIZE_STAGINGWORKER", 50).to_i,
)

T.unsafe(self).worker_factory do |queues|
  queue_strategies = [
    GitHub::Aqueduct::QueueStrategies::QueueMemoization.new, # memoize but refresh occasionally
    GitHub::Aqueduct::QueueStrategies::QueuePrioritization.new(prioritize_by: prioritize_by),
    GitHub::Aqueduct::QueueStrategies::QueueSubsetSelection.new(
      queue_subset_selector: queue_subset_selector,
      prioritize_by: prioritize_by
    ),
    GitHub::Aqueduct::QueueStrategies::QueueShuffle.new, # shuffle each time
  ]
  Resqued::AqueductWorkerAdapter.new(
    *queues,
    backend: GitHub.aqueduct_staging_worker_backend(queue_strategies: queue_strategies),
  )
end

T.unsafe(self).worker_pool ENV.fetch("RESQUED_STAGING_WORKER_POOL_SIZE", 10).to_i, shuffle_queues: true

BackgroundJobQueues.apply_staging(self, worker_role: :stagingworker, machine_type: :kube)
