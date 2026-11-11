# typed: true
# frozen_string_literal: true

require_relative "./worker_metrics"

module Resqued
  class MetricsReporter
    def self.start(poll_interval: 15)
      instance = new
      Thread.new do # rubocop:disable GitHub/ThreadUse
        loop do
          instance.report
          GC.start # otherwise `ps`'s output sticks around and this process's RSS may try to eat up a big chunk of what's available.
          sleep poll_interval
        end
      end
    end

    # magic: - optional string, used for testing to match specific test worker processes
    # deployable: - optional boolean, used for testing to force a specific deployable value
    def initialize(magic: nil, deployable: nil)
      @magic = magic
      @deployable = deployable
    end

    def report
      get_procs = Resqued::WorkerMetrics::DEFAULT_GET_PROCS
      get_metadata = Resqued::WorkerMetrics::DEFAULT_GET_METADATA

      if @magic
        get_procs = -> { Resqued::WorkerMetrics::DEFAULT_GET_PROCS.call.grep(Regexp.new(@magic)) }
      end

      if @deployable
        get_metadata = -> { { "attributes" => { "github" => { "deployable" => true } } } }
      end

      metrics = Resqued::WorkerMetrics.new(get_procs: get_procs, get_metadata: get_metadata)
      results = metrics.generate

      results.aqueduct_workers_by_state.each do |stat|
        tags = ["state:#{stat.state}", "listener_state:#{stat.listener_state}"]
        tags << "backend:#{stat.backend}" if stat.backend
        GitHub.dogstats.gauge("aqueduct.workers.by_state.count", stat.count, tags: tags)
      end

      tags = []
      tags << "deployable:#{results.deployable}" if results.deployable != nil
      GitHub.dogstats.gauge("aqueduct.workers.count", results.aqueduct_total_workers, tags: tags)
      GitHub.dogstats.gauge("aqueduct.workers.idle.count", results.aqueduct_idle_workers)
      GitHub.dogstats.gauge("aqueduct.workers.active.count", results.aqueduct_active_workers)
      GitHub.dogstats.gauge("aqueduct.workers.stale.count", results.aqueduct_stale_workers)
      GitHub.dogstats.gauge("aqueduct.listeners.stalled.count", results.aqueduct_stalled_listeners)

      results.aqueduct_workers_by_shard.each do |stat|
        tags = []
        tags << "backend:#{stat.backend}" if stat.backend
        tags << "shard:#{stat.shard}" if stat.shard
        GitHub.dogstats.gauge("aqueduct.workers.by_shard.count", stat.count, tags: tags)
      end

      results.aqueduct_active_workers_by_shard.each do |stat|
        tags = []
        tags << "backend:#{stat.backend}" if stat.backend
        tags << "shard:#{stat.shard}" if stat.shard
        GitHub.dogstats.gauge("aqueduct.workers.active.by_shard.count", stat.count, tags: tags)
      end

      results.aqueduct_active_workers_by_queue.each do |stat|
        tags = []
        tags << "queue:#{stat.queue}" if stat.queue
        GitHub.dogstats.gauge("aqueduct.workers.active.by_queue.count", stat.count, tags: tags)
      end
    end
  end
end
