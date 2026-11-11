# typed: true
# frozen_string_literal: true

# Configuration for hookworker deployment in Azure Lab. Loads after github-environment.rb.
# This is a low-throughput configuration for testing Azure deployments.

require "resqued/metrics_server"
require "resqued/worker_readiness"

GitHub.role = :hookworker
Aqueduct::Worker.configure do |config|
  config.worker_pool = "github-hookworker-azure-lab"
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

# Limited to 1 worker for low-throughput testing
T.unsafe(self).worker_pool ENV.fetch("RESQUED_WORKER_POOL_SIZE", 1).to_i, shuffle_queues: true

# Only process deliver_hook_event queue in azure-lab
T.unsafe(self).queue "deliver_hook_event"
