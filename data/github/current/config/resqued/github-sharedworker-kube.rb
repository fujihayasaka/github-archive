# typed: true
# frozen_string_literal: true

# Shared resqued worker pool for all workers in a specific stamp. Loads after github-environment.rb.

GitHub.role = :sharedworker
DEFAULT_WORKER_POOL_STAMP_ENVIRONMENT = "proxima"
ALLOWED_WORKER_POOL_STAMP_ENVIRONMENT = %w[dotcom proxima].freeze

Aqueduct::Worker.configure do |config|
  config.worker_pool = "github-sharedworker-kube"
end

# Provide aqueduct.workers.count metrics
T.unsafe(self).before_fork { Resqued::MetricsServer.start }

# Drop a file on disk to indicate that the workers are ready.
T.unsafe(self).after_fork { |_worker| Resqued::WorkerReadiness.report_ready }

T.unsafe(self).worker_factory do |queues|
  Resqued::AqueductWorkerAdapter.new(
    *queues,
    prioritize_by: Resqued::ShouldStartWithinPriority.new(buckets: %w[30m 2h]),
    queue_subset_selector: Resqued::QueueSubsetSelector.new(
      queue_subset_size: ENV.fetch("RESQUED_QUEUE_SUBSET_SIZE_SHAREDWORKER", 50).to_i
    ),
  )
end

T.unsafe(self).worker_pool ENV.fetch("RESQUED_SHAREDWORKER_POOL_SIZE", 10).to_i, shuffle_queues: true

worker_pool_stamp_environment = ENV["WORKER_POOL_STAMP_ENVIRONMENT"] || DEFAULT_WORKER_POOL_STAMP_ENVIRONMENT
if !ALLOWED_WORKER_POOL_STAMP_ENVIRONMENT.include?(worker_pool_stamp_environment)
  raise "Invalid worker pool stamp environment: #{worker_pool_stamp_environment}. Must be one of: #{ALLOWED_WORKER_POOL_STAMP_ENVIRONMENT.join(", ")}"
end

BackgroundJobQueues.apply_worker_pool_env(self, environment: worker_pool_stamp_environment.to_sym, worker_role: :sharedworker, machine_type: :kube)
