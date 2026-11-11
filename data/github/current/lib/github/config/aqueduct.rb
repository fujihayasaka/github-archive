# typed: false
# frozen_string_literal: true

require "aqueduct"
require "github/aqueduct/status_server"

# Worker Observability Metrics
#
# job.warmup.time_ms - Job execution time during warmup phase (first N jobs after restart,
#   where N is WARMUP_JOB_COUNT_THRESHOLD, currently 10)
#   Tags: warmup_phase, jobs_since_restart
#   Use: Compare against steady-state to measure warmup tax
#
# job.memory_delta_bytes - Memory change from before to after job execution
#   Use: Identify memory-hungry jobs
#
# worker.memory_bucket - Memory utilization bucket at job completion
#   Tags: bucket (<40pct, 40-60pct, 60-80pct, 80-95pct, >=95pct)
#   Use: Correlate performance degradation with memory pressure
#
# job.time_by_memory_bucket - Job execution time by memory bucket
#   Tags: bucket (<40pct, 40-60pct, 60-80pct, 80-95pct, >=95pct)
#   Use: Identify if jobs slow down as workers approach memory limit
#
# job.cache_hit_rate_pct - Cache hit rate for the job
#   Tags: phase (warmup/steady_state), jobs_since_restart
#   Use: Measure cache effectiveness during warmup vs steady state
#
# worker.time_to_first_job_ms - Time from worker ready to first job execution
#   Use: Measure queue wait time during cold starts
#
# aqueduct.graceful_exit.overage_pct - How far over memory limit when shutdown triggered
#   Use: Understand memory overage patterns

# Helper module for shared memory bucket calculation
module AqueductMemoryBucketHelper
  # Number of jobs after restart that are considered "warmup" phase
  # Jobs during warmup typically have lower cache hit rates and slower performance
  WARMUP_JOB_COUNT_THRESHOLD = 10

  module_function

  def memory_bucket_for(memrss, memrss_limit)
    memory_pct = (memrss.to_f / memrss_limit * 100).round
    case memory_pct
    when 0...40 then "<40pct"
    when 40...60 then "40-60pct"
    when 60...80 then "60-80pct"
    when 80...95 then "80-95pct"
    else ">=95pct"
    end
  end
end

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

    # Add extra artificial backoff time if enabled (60s)
    # This is to help with the case where we have a lot of workers asking for empty queues
    # and we want to reduce the number of concurrent blocking dequeue requests.
    # This is not a replacement for the backoff above and should be used in addition to it by the
    # Data Pipelines team.
    if GitHub.aqueduct_worker_artificial_backoff_on_queues_empty?
      60.times do
        break if worker.shutdown?
        sleep 1
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
    # Store worker reference for access in job callbacks
    Thread.current[:aqueduct_worker] = worker

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

  config.before_perform do |worker, job|
    # Track jobs-since-restart to identify warm-up phase
    # This helps quantify the "warm-up tax" when workers restart due to high memory
    # rubocop:disable GitHub/AvoidDynamicInstanceVariableMethods
    worker.instance_variable_set(:@jobs_count, 0) unless worker.instance_variable_defined?(:@jobs_count)
    jobs_count = worker.instance_variable_get(:@jobs_count)
    worker.instance_variable_set(:@jobs_count, jobs_count + 1)

    # Track time-to-first-job: time between worker ready and first job execution
    if jobs_count == 0 && Thread.current[:worker_ready_at]
      tags = GitHub.aqueduct_tags
      ttfj_ms = (Time.now - Thread.current[:worker_ready_at]) * 1000
      GitHub.dogstats.distribution("worker.time_to_first_job_ms", ttfj_ms, tags: tags)
      Thread.current[:worker_ready_at] = nil # Clear after first job
    end

    # Track memory before job execution to measure per-job memory growth
    memrss_before = GitHub::Memory.memrss
    worker.instance_variable_set(:@memrss_before_job, memrss_before)

    # Store job metadata for after_perform memory metrics (which doesn't receive the job arg).
    # job is an Aqueduct::Worker::Job; extract the real job class from the payload.
    job_class = begin
      GitHub::JSON.decode(job.payload).fetch("job_class", job.class.name)
    rescue
      job.class.name
    end
    worker.instance_variable_set(:@last_job_class, job_class)
    worker.instance_variable_set(:@last_job_queue, job.queue)
    # rubocop:enable GitHub/AvoidDynamicInstanceVariableMethods

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

    # Include job class and queue in memory metrics for per-job analysis
    # rubocop:disable GitHub/AvoidDynamicInstanceVariableMethods
    if worker.instance_variable_defined?(:@last_job_class)
      tags = tags.merge(
        "job_class" => worker.instance_variable_get(:@last_job_class),
        "queue" => worker.instance_variable_get(:@last_job_queue),
      )
    end
    # rubocop:enable GitHub/AvoidDynamicInstanceVariableMethods

    memrss = GitHub::Memory.memrss
    memrss_limit = GitHub.job_worker_graceful_memory_limit
    GitHub.dogstats.distribution("worker.memrss", memrss, tags: tags)
    GitHub.dogstats.distribution("worker.memrss_limit", memrss_limit, tags: tags)

    # Track per-job memory delta to identify memory-hungry jobs
    # rubocop:disable GitHub/AvoidDynamicInstanceVariableMethods
    if worker.instance_variable_defined?(:@memrss_before_job)
      memrss_before = worker.instance_variable_get(:@memrss_before_job)
      memory_delta = memrss - memrss_before
      GitHub.dogstats.distribution("job.memory_delta_bytes", memory_delta, tags: tags)
    end
    # rubocop:enable GitHub/AvoidDynamicInstanceVariableMethods

    # Track memory bucket for performance correlation
    # Shows if workers slow down as they approach the memory limit
    memory_pct = (memrss.to_f / memrss_limit * 100).round
    memory_bucket = AqueductMemoryBucketHelper.memory_bucket_for(memrss, memrss_limit)
    GitHub.dogstats.gauge("worker.memory_bucket", memory_pct, tags: tags.merge("bucket" => memory_bucket))

    if memrss > memrss_limit
      # Track how far over the limit we went before shutdown
      overage_pct = ((memrss - memrss_limit).to_f / memrss_limit * 100).round
      GitHub.dogstats.distribution("aqueduct.graceful_exit.memrss", memrss, tags: tags)
      GitHub.dogstats.distribution("aqueduct.graceful_exit.overage_pct", overage_pct, tags: tags)
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

  # Helper method to calculate memory bucket based on memory usage percentage
  def memory_bucket_for(memrss, memrss_limit)
    AqueductMemoryBucketHelper.memory_bucket_for(memrss, memrss_limit)
  end

  # Helper method to calculate total cache hits from the query_hits hash
  def total_cache_hits
    return 0 unless defined?(GitHub::Cache::Client)
    query_hits = GitHub::Cache::Client.query_hits
    return 0 unless query_hits
    query_hits.values.sum
  end

  # Helper method to check if cache metrics can be collected
  def cache_metrics_available?(cache_queries_before, cache_hits_before)
    defined?(GitHub::Cache::Client) && !cache_queries_before.nil? && !cache_hits_before.nil?
  end

  # Helper method to emit cache hit rate metrics
  def emit_cache_hit_rate_metric(cache_queries_before, cache_hits_before, warmup_phase, jobs_count, extra_tags = [])
    return unless cache_metrics_available?(cache_queries_before, cache_hits_before)

    cache_queries = GitHub::Cache::Client.query_count - cache_queries_before
    cache_hits = total_cache_hits - cache_hits_before
    return unless cache_queries > 0

    cache_hit_rate = (cache_hits.to_f / cache_queries * 100).round(2)
    warmup_tag = warmup_phase ? "warmup" : "steady_state"
    tags = ["phase:#{warmup_tag}", "jobs_since_restart:#{jobs_count}"] + extra_tags
    GitHub.dogstats.distribution("job.cache_hit_rate_pct", cache_hit_rate, tags: tags)
  end

  # Helper method to emit warmup phase metrics
  def emit_warmup_metrics(warmup_phase, timer, jobs_count, extra_tags = [])
    return unless warmup_phase

    tags = ["warmup_phase:true", "jobs_since_restart:#{jobs_count}"] + extra_tags
    GitHub.dogstats.distribution("job.warmup.time_ms", timer.elapsed_ms, tags: tags)
  end

  # Helper method to emit memory bucket performance metrics
  def emit_memory_bucket_performance_metric(worker, timer, extra_tags = [])
    return unless worker && GitHub.job_worker_graceful_memory_limit

    memrss = GitHub::Memory.memrss
    memory_bucket = memory_bucket_for(memrss, GitHub.job_worker_graceful_memory_limit)
    tags = ["bucket:#{memory_bucket}"] + extra_tags
    GitHub.dogstats.distribution("job.time_by_memory_bucket", timer.elapsed_ms, tags: tags)
  end

  # Shared method to track and emit all warmup/performance metrics after job execution
  # This reduces duplication between ActiveJob and Kafka consumer lifecycle callbacks
  # @param timer [Timer] The job execution timer
  # @param cache_queries_before [Integer, nil] Cache query count before job execution
  # @param cache_hits_before [Integer, nil] Cache hits count before job execution
  # @param extra_tags [Array<String>] Additional tags to include with metrics
  def track_and_emit_performance_metrics(timer, cache_queries_before: nil, cache_hits_before: nil, extra_tags: [])
    if ENV["CI"] && GitHub.enterprise?
      $stderr.puts "[DEBUG track_and_emit_performance_metrics] ENTER"
    end

    worker = Thread.current[:aqueduct_worker]

    if ENV["CI"] && GitHub.enterprise?
      $stderr.puts "[DEBUG track_and_emit_performance_metrics] worker=#{worker.class.name rescue 'nil'}, worker.nil?=#{worker.nil?}"
    end

    # rubocop:disable GitHub/AvoidDynamicInstanceVariableMethods
    jobs_count = worker&.instance_variable_get(:@jobs_count) || 0
    # rubocop:enable GitHub/AvoidDynamicInstanceVariableMethods

    if ENV["CI"] && GitHub.enterprise?
      $stderr.puts "[DEBUG track_and_emit_performance_metrics] jobs_count=#{jobs_count}, WARMUP_JOB_COUNT_THRESHOLD=#{AqueductMemoryBucketHelper::WARMUP_JOB_COUNT_THRESHOLD}"
    end

    warmup_phase = jobs_count <= AqueductMemoryBucketHelper::WARMUP_JOB_COUNT_THRESHOLD

    if ENV["CI"] && GitHub.enterprise?
      $stderr.puts "[DEBUG track_and_emit_performance_metrics] warmup_phase=#{warmup_phase}"
      $stderr.puts "[DEBUG track_and_emit_performance_metrics] About to call emit_cache_hit_rate_metric"
    end

    emit_cache_hit_rate_metric(cache_queries_before, cache_hits_before, warmup_phase, jobs_count, extra_tags)

    if ENV["CI"] && GitHub.enterprise?
      $stderr.puts "[DEBUG track_and_emit_performance_metrics] About to call emit_warmup_metrics"
    end

    emit_warmup_metrics(warmup_phase, timer, jobs_count, extra_tags)

    if ENV["CI"] && GitHub.enterprise?
      $stderr.puts "[DEBUG track_and_emit_performance_metrics] About to call emit_memory_bucket_performance_metric"
    end

    emit_memory_bucket_performance_metric(worker, timer, extra_tags)

    if ENV["CI"] && GitHub.enterprise?
      $stderr.puts "[DEBUG track_and_emit_performance_metrics] EXIT SUCCESS"
    end
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
      original_vexi_memoizing = FeatureFlag.vexi.memoizing?
      FeatureFlag.vexi.memoize = true
      yield
    ensure
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
    # DEBUG: Log entry
    if ENV["CI"] && GitHub.enterprise?
      $stderr.puts "[DEBUG publish_performed_notification] ENTER job_class=#{job_class}"
    end

    timer = Timer.start
    started_at = timer.started_at

    pre_perform_allocation_count = GC.stat(:total_allocated_objects)
    GitHub::JobStats.memory_usage_reset(job_class: job_class)

    # Capture cache stats before job execution for performance metrics
    cache_queries_before = GitHub::Cache::Client.query_count if defined?(GitHub::Cache::Client)
    cache_hits_before = total_cache_hits if defined?(GitHub::Cache::Client)

    if ENV["CI"] && GitHub.enterprise?
      $stderr.puts "[DEBUG publish_performed_notification] cache_queries_before=#{cache_queries_before.inspect}, cache_hits_before=#{cache_hits_before.inspect}"
    end

    begin
      if ENV["CI"] && GitHub.enterprise?
        $stderr.puts "[DEBUG publish_performed_notification] About to yield to job.perform"
      end
      yield
      if ENV["CI"] && GitHub.enterprise?
        $stderr.puts "[DEBUG publish_performed_notification] Job.perform completed successfully"
      end
    rescue => job_error
      if ENV["CI"] && GitHub.enterprise?
        $stderr.puts "[DEBUG publish_performed_notification] Job.perform raised: #{job_error.class.name}: #{job_error.message}"
      end
      raise
    ensure
      if ENV["CI"] && GitHub.enterprise?
        $stderr.puts "[DEBUG publish_performed_notification] In ensure block"
      end

      timer.stop
      GitHub::JobStats.memory_usage_snapshot

      # Emit all warmup and performance metrics via shared helper
      begin
        if ENV["CI"] && GitHub.enterprise?
          $stderr.puts "[DEBUG publish_performed_notification] About to call track_and_emit_performance_metrics"
        end
        track_and_emit_performance_metrics(timer,
          cache_queries_before: cache_queries_before,
          cache_hits_before: cache_hits_before)
        if ENV["CI"] && GitHub.enterprise?
          $stderr.puts "[DEBUG publish_performed_notification] track_and_emit_performance_metrics completed"
        end
      rescue => metrics_error
        if ENV["CI"] && GitHub.enterprise?
          $stderr.puts "[DEBUG publish_performed_notification] track_and_emit_performance_metrics FAILED: #{metrics_error.class.name}: #{metrics_error.message}"
          $stderr.puts "[DEBUG publish_performed_notification] Backtrace: #{metrics_error.backtrace&.first(10)&.join("\n")}"
        end
        # Don't re-raise metrics errors - they shouldn't fail the job
      end

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

    # Capture cache stats before job execution for performance metrics
    cache_queries_before = GitHub::Cache::Client.query_count if defined?(GitHub::Cache::Client)
    cache_hits_before = total_cache_hits if defined?(GitHub::Cache::Client)

    begin
      yield
    ensure
      timer.stop
      GitHub::JobStats.memory_usage_snapshot

      # Emit all warmup and performance metrics via shared helper
      track_and_emit_performance_metrics(timer,
        cache_queries_before: cache_queries_before,
        cache_hits_before: cache_hits_before,
        extra_tags: ["topic:#{topic}"])

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
