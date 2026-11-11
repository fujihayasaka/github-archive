# typed: true
# frozen_string_literal: true

# Configuration for hookworker deployment in Kubernetes. Loads after github-environment.rb.

require "resqued/metrics_server"
require "resqued/worker_readiness"

DEFAULT_WORKER_POOL_STAMP_ENVIRONMENT = "dotcom"
ALLOWED_WORKER_POOL_STAMP_ENVIRONMENT = %w[dotcom proxima].freeze

GitHub.role = :hookworker

worker_pool_stamp_environment = ENV["WORKER_POOL_STAMP_ENVIRONMENT"] || DEFAULT_WORKER_POOL_STAMP_ENVIRONMENT
if !ALLOWED_WORKER_POOL_STAMP_ENVIRONMENT.include?(worker_pool_stamp_environment)
  raise "Invalid worker pool stamp environment: #{worker_pool_stamp_environment}. Must be one of: #{ALLOWED_WORKER_POOL_STAMP_ENVIRONMENT.join(", ")}"
end

Aqueduct::Worker.configure do |config|
  config.worker_pool = "github-hookworker"
end

# Provide aqueduct.workers.count metrics
T.unsafe(self).before_fork { Resqued::MetricsServer.start }

# Drop a file on disk to indicate that the workers are ready.
T.unsafe(self).after_fork { |_worker| Resqued::WorkerReadiness.report_ready }

T.unsafe(self).worker_factory do |queues|
  Resqued::AqueductWorkerAdapter.new(
    *queues,
    prioritize_by: Resqued::ShouldStartWithinPriority.new(buckets: %w[1m 10m 30m])
  )
end

T.unsafe(self).worker_pool ENV.fetch("RESQUED_WORKER_POOL_SIZE", 10).to_i, shuffle_queues: true

BackgroundJobQueues.apply_worker_pool_env(self, environment: worker_pool_stamp_environment.to_sym, worker_role: :hookworker, machine_type: :kube)
