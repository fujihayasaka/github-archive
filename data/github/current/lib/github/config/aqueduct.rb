# typed: false
# frozen_string_literal: true

require "aqueduct"
require "github/aqueduct/status_server"

Aqueduct::Worker.configure do |config|
  config.heartbeat_check_interval_seconds = 5.seconds
  config.heartbeat_interval_seconds = GitHub::Aqueduct::Job::HEARTBEAT_INTERVAL
  config.handler = ->(job, status) { GitHub::Aqueduct::Job.execute(job, status) }
  config.procline = ->(version) do
    if GitHub::JobStats.backend_name.blank?
      "#{version} [#{GitHub.current_sha[0, 7]}]"
    else
      "#{version} [#{GitHub.current_sha[0, 7]}] [#{GitHub::JobStats.backend_name}]"
    end
  end

  config.error_reporter = ->(err, _job) {
    if err.is_a?(Aqueduct::Client::ClientError)
      Failbot.report(err, {
        app: "github-aqueduct",
      }.merge(err.metadata.map { |k, v| ["aqueduct_#{k}", v] }.to_h))
    else
      Failbot.report(err)
    end
  }

  config.invalid_payload_policy = :ignore

  config.on_invalid_payload do |_worker, job|
    tags = ["queue:#{job.queue}"]
    GitHub.dogstats.increment "aqueduct.hmac_mismatch", tags: tags
    GitHub.logger.info("aqueduct HMAC validation failed", { "gh.job.queue" => job.queue, "gh.job.aqueduct_id" => job.id })
  end

  # set by `cant_fork=` in AqueductWorkerAdapter.
  # config.fork_per_job = false

  config.after_startup do |worker|
    # Need to chdir under enterprise due to upgrade switching out dir inodes
    Dir.chdir Rails.root if GitHub.enterprise?

    if GitHub.enable_aqueduct_status_server?
      Thread.new { GitHub::Aqueduct::StatusServer.new(worker: worker).run } # rubocop:disable GitHub/ThreadUse
    end

    if GitHub.aqueduct_worker_backoff_on_queues_empty?
      # Stagger startup for DFS workers that perform cooperative backoff to avoid request spikes
      # following github deploys and to offset requests.
      rand(30).times do
        sleep 1 unless worker.shutdown?
      end
    end

    GitHub::DataCollector.enable_all

    GitHub::InstrumentationThread.start
  end

  config.queues_empty do |worker|
    if GitHub.aqueduct_worker_backoff_on_queues_empty?
      # Sleep for 60 seconds after a dequeue fails to return a job. The goal is to reduce the
      # number of concurrent blocking dequeue requests issued by DFS workers that are mostly idle.
      60.times do
        sleep 1 unless worker.shutdown?
      end
    end
  end

  # config.before_fork do
  # we only fork in development, and reconnects happen in before_perform
  # end

  # config.after_fork do
  # not used, we only fork in development
  # end

  config.before_pop do |worker|
    # Stop the worker if it becomes an orphan and prevent it from running old code on baremetal deploys,
    # since the resqued master doesn't clean up orphaned workers. This works as long as a job doesn't hang indefinitely,
    # which has happened, but very infrequently.
    # A process's ppid will be set to 1 if its parent process exits unexpectedly as long as the worker process chain
    # (systemd, resqued master, resqued listener, etc) doesn't call PR_SET_CHILD_SUBREAPER.
    # See https://man7.org/linux/man-pages/man2/prctl.2.html#DESCRIPTION for more details.
    if Process.ppid == 1
      tags = GitHub.aqueduct_tags
      tags["orphaned"] = "true"
      GitHub.dogstats.increment("aqueduct.graceful_exit", tags: tags)
      # aqueduct-client-ruby shutdown check happens before :before_pop
      GitHub::Logger.log(msg: "worker with pid #{Process.pid} has become orphaned; it will exit after the next job attempt")
      worker.shutdown
    end

    worker.backend.maybe_switch_backends if worker.backend.respond_to?(:maybe_switch_backends)
  end

  config.before_perform do |worker, _job|
    # Reset the Failbot context before each job run.
    Failbot.reset_context
    Failbot.push worker: worker.to_s

    # Start a publishing batch for more efficient publishing of events from
    # within a job.
    if GitHub.hydro_enabled?
      GitHub.hydro_publisher.start_batch
    end
  end

  config.after_perform do |worker|
    if GitHub.hydro_enabled?
      result = GitHub.hydro_publisher.flush_batch
      if result && !result.success?
        GitHub.report_hydro_error(result.error)
      end
    end

    next if GitHub.job_worker_graceful_memory_limit.nil?

    tags = GitHub.aqueduct_tags

    memrss = GitHub::Memory.memrss
    memrss_limit = GitHub.job_worker_graceful_memory_limit
    GitHub.dogstats.distribution("worker.memrss", memrss, tags: tags)
    GitHub.dogstats.distribution("worker.memrss_limit", memrss_limit, tags: tags)

    if memrss > memrss_limit
      GitHub.dogstats.distribution("aqueduct.graceful_exit.memrss", memrss, tags: tags)
      GitHub.dogstats.increment("aqueduct.graceful_exit", tags: tags)
      worker.shutdown
    end

    Failbot.reset_context
  end
end

module AqueductCommonLifecycleCallbacks
  extend ActiveSupport::Concern

  included do
    around_execute :set_github_component
    around_execute :memoize_feature_flags
    around_execute :reset_counters
  end

  def set_github_component
    original_component = GitHub.component
    GitHub.component = GitHub::Aqueduct::COMPONENT
    yield
  ensure
    GitHub.component = original_component
  end

  def memoize_feature_flags
    begin
      original_flipper_memoizing = GitHub.flipper.adapter.memoizing?
      original_vexi_memoizing = FeatureFlag.vexi.memoizing?
      GitHub.flipper.adapter.memoize = true
      FeatureFlag.vexi.memoize = true
      yield
    ensure
      GitHub.flipper.adapter.memoize = original_flipper_memoizing
      FeatureFlag.vexi.memoize = original_vexi_memoizing
    end
  end

  def reset_counters
    GitHub::DataCollector.reset_all
    yield
  end

  def freno_stats
    {
      throttle_calls_by_cluster: GitHub::FrenoInstrumenter.throttle_calls_by_cluster,
      total_waited_ms_by_cluster: GitHub::FrenoInstrumenter.total_waited_by_cluster.transform_values { |t| (t * 1000).round },
      timeouts_by_cluster: GitHub::FrenoInstrumenter.timeouts_by_cluster,
      errors_by_cluster: GitHub::FrenoInstrumenter.errors_by_cluster,
      open_circuits_by_cluster: GitHub::FrenoInstrumenter.open_circuits_by_cluster,
    }
  end

  def mysql_stats
    {
      db_counts: GitHub::MysqlInstrumenter.queries_per_type_database,
      query_count: GitHub::MysqlInstrumenter.query_count,
      primary_query_count: GitHub::MysqlInstrumenter.primary_query_count,
      query_time_ms: (GitHub::MysqlInstrumenter.query_time * 1000).round,
      queries_count_by_type: GitHub::MysqlInstrumenter.queries_per_type_database,
      query_count_by_db: GitHub::MysqlInstrumenter.queries_per_database,
      query_times_ms_by_db: GitHub::MysqlInstrumenter.query_times_per_database.transform_values { |t| (t * 1000).round },
    }
  end

  def rpc_stats
    {
      gitrpc_count: GitRPCLogSubscriber.rpc_count,
      gitrpc_time_ms: (GitRPCLogSubscriber.rpc_time * 1000).round,
    }
  end
end

module AqueductActiveJobLifecycleCallbacks
  extend ActiveSupport::Concern

  included do
    before_execute :set_procline
    before_execute :configure_contexts
    before_execute :configure_failbot
    before_execute :publish_dequeued_notification
    around_execute :publish_performed_notification
  end

  def set_procline
    # Append the current class to the procline while executing. This is reset
    # by Aqueduct::Worker after the job is completed.
    $0 = "#{$0}: #{job_class}"
  end

  def configure_contexts
    job_context = {
      job: job_class,
      active_job_id: active_job_id_from_payload,
      aqueduct_job_id: aqueduct_job_id,
      catalog_service: catalog_service
    }

    audit_context = metadata.fetch("audit_context", {}).merge(job_context)
    github_context = metadata.fetch("context", {}).merge(job_context)

    github_context = github_context.symbolize_keys

    Audit.context.reset
    Audit.context.push(audit_context)

    GitHub.context.reset
    GitHub.context.push(github_context)

    SensitiveData.context.reset
  end

  def configure_failbot
    queue_time = nil
    if (queued_at = metadata["queued_at"])
      queue_time = Time.now - Time.at(queued_at)
    end

    context = metadata["context"]

    Failbot.push(
      queue: queue,
      queue_time: queue_time,
      queued_from: (context && context["from"]),
      rails: Rails.version,
      request_id: (context && context["request_id"]),
      "#job": job_class, # #job for tagged search in sentry
    )
  end

  def publish_dequeued_notification
    if metadata["queued_at"] != nil
      GitHub.publish(
        "dequeued.background_job",
        Time.at(metadata["deliver_at"] || metadata["queued_at"]),
        Time.now,
        SecureRandom.hex(10),
        queue: queue,
        class: job_class.underscore,
        backend: :aqueduct,
        catalog_service: catalog_service,
      )
    end
  end

  def publish_performed_notification
    timer = Timer.start
    started_at = timer.started_at

    pre_perform_allocation_count = GC.stat(:total_allocated_objects)
    GitHub::JobStats.memory_usage_reset(job_class: job_class)

    begin
      yield
    ensure
      timer.stop
      GitHub::JobStats.memory_usage_snapshot

      GitHub.publish("performed.background_job",
                     started_at,
                     Time.now,
                     SecureRandom.hex(10),
                     queue: @queue,
                     class: job_class.underscore,
                     success: !GitHub::JobStats.fatal_error?,
                     pre_perform_allocation_count: pre_perform_allocation_count,
                     backend: :aqueduct,
                     catalog_service: catalog_service,
                     timer: timer,
                     freno_stats: freno_stats,
                     mysql_stats: mysql_stats,
                     rpc_stats: rpc_stats,
                    )

      GlobalInstrumenter.instrument("performed.job", {
        queue: @queue,
        job_class: job_class.to_s,
        aqueduct_job_id: aqueduct_job_id,
        active_job_id: active_job_id_from_payload,
        timer: timer,
        success: !GitHub::JobStats.error,
        catalog_service: catalog_service,
        freno_stats: freno_stats,
        mysql_stats: mysql_stats,
        rpc_stats: rpc_stats,
      })
    end
  end

  private

  def active_job_id_from_payload
    payload["job_id"]
  end

  def catalog_service
    GitHub.serviceowners&.service_for_class(job_class, prefix: true) || GitHub::Serviceowners::UNKNOWN_SERVICE
  end
end

module AqueductHydroMessageJobLifecycleCallbacks
  extend ActiveSupport::Concern

  included do
    before_execute :set_procline
    before_execute :configure_failbot
    before_execute :configure_contexts
    around_execute :configure_query_logs
    around_execute :publish_performed_notification
  end

  def set_procline
    # This is reset by Aqueduct::Worker after the job is completed.
    $0 = "#{$0}: #{job_class.name} #{topic}:#{partition}:#{offset}"
  end

  def configure_failbot
    Failbot.push(
      queue: queue,
      rails: Rails.version,
      kafka_cluster: kafka_cluster,
      "#job": job_class.name,
      topic: topic,
      partition: partition,
      offset: offset,
      catalog_service: catalog_service
    )
  end

  def configure_contexts
    job_context = {
      job: job_class.name,
      aqueduct_job_id: aqueduct_job_id,
      kafka_cluster: kafka_cluster,
      topic: topic,
      partition: partition,
      offset: offset,
      catalog_service: catalog_service
    }

    Audit.context.reset
    Audit.context.push(job_context)

    GitHub.context.reset
    GitHub.context.push(job_context)

    SensitiveData.context.reset
  end

  def configure_query_logs(&block)
    ActiveSupport::ExecutionContext.set(job: job_instance, &block)
  end

  def publish_performed_notification
    timer = Timer.start

    # We need to capture started_at so we can use job duration time in different parts of the code.
    #   E.g. Datadog metric reporting, stats on JobComplete, etc
    # This is a limitation of how our current timer works.
    started_at = timer.started_at

    pre_perform_allocation_count = GC.stat(:total_allocated_objects)
    GitHub::JobStats.memory_usage_reset(job_class: job_class.name)

    begin
      yield
    ensure
      timer.stop
      GitHub::JobStats.memory_usage_snapshot

      GitHub.publish("performed.background_job",
                     started_at,
                     Time.now,
                     SecureRandom.hex(10),
                     queue: queue,
                     class: job_class.name.underscore,
                     success: !GitHub::JobStats.fatal_error?,
                     pre_perform_allocation_count: pre_perform_allocation_count,
                     backend: :aqueduct,
                     topic: topic,
                     catalog_service: catalog_service,
                     timer: timer,
                     freno_stats: freno_stats,
                     mysql_stats: mysql_stats,
                     rpc_stats: rpc_stats,
                    )

      GlobalInstrumenter.instrument("performed.job", {
        queue: queue,
        job_class: job_class.name,
        aqueduct_job_id: aqueduct_job_id,
        timer: timer,
        success: !GitHub::JobStats.error,
        catalog_service: catalog_service,
        mysql_stats: mysql_stats,
        freno_stats: freno_stats,
        rpc_stats: rpc_stats,
      })
    end
  end

  private

  def catalog_service
    GitHub.serviceowners&.service_for_class(job_class, prefix: true) || GitHub::Serviceowners::UNKNOWN_SERVICE
  end
end

# These callbacks are implemented as a module rather than directly defined in
# the Job class itself so that the lifecycle configuration can live in the same
# place as the Aqueduct::Worker configuration.

GitHub::Aqueduct::Job.module_eval do
  include AqueductCommonLifecycleCallbacks
end

GitHub::Aqueduct::ActiveJobContext.module_eval do
  include AqueductActiveJobLifecycleCallbacks
end

GitHub::Aqueduct::HydroMessageJobContext.module_eval do
  include AqueductHydroMessageJobLifecycleCallbacks
end
