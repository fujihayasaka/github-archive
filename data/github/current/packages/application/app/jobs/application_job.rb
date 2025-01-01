# typed: false
# frozen_string_literal: true

require "active_job"
require "active_job/tenant_context"
require "active_job/locking_job"
require "active_job/performance_result"
require "active_job/scheduled_job"
require "active_job/initially_enqueued_at"
require "active_job/job_class_actor"

require "github/service_mapping"
require "github/throttler"
require "background_job_queues"

class ApplicationJob < ActiveJob::Base

  class InvalidClusterError < StandardError; end

  # Preserves tenant context; prepends overrides for serialization
  include ActiveJob::TenantContext
  include GitHub::ServiceMapping
  include ActiveJob::LockingJob
  include ActiveJob::PerformanceResult
  include ActiveJob::ScheduledJob
  include SmartDatabaseSelection
  include SetZuoraBackgroundClient

  DEFAULT_TIMEOUT = 1.hour

  # These queue names aren't set in job classes but are referred to explicitly
  # during enqueue.
  MONITOR_QUEUE_NAMES = BackgroundJobQueues.monitor_queue_names
  ALLOWED_QUEUE_NAMES = %w[
    dependabot_alerts_backfill
    dgit_repairs
    high
    background_destroy
    background_destroy_issues_pull_requests
    background_destroy_repositories
    background_destroy_repositories_pushes
    background_destroy_mysql1
    octoshift
    pages-docker
    signup_emails
    spam
    team_member_added_emails
    test
  ].concat(MONITOR_QUEUE_NAMES) # WARNING: make sure these queues are added to /config/resqued/* or config/background_job_queues/*

  before_enqueue do
    klass_queue_name = self.class.queue_name
    klass_queue_name = instance_exec(&klass_queue_name) if klass_queue_name.is_a?(Proc)
    next if queue_name == klass_queue_name
    # indexing jobs switch between different queues:
    next if queue_name.start_with?("index_") && klass_queue_name.start_with?("index_")
    next if queue_name.start_with?("maint") # dgit-related jobs
    next if ALLOWED_QUEUE_NAMES.include?(queue_name)
    err = ArgumentError.new "queue: '#{queue_name}' is not recognized"
    if GitHub.raise_on_unrecognized_queue?
      raise err
    else
      Failbot.report(err, {
        app: "github-legacy-jobs",
        job_class: self.class,
      })
    end
  end

  around_enqueue do |job, block|
    if GitHub.respond_to?(:flipper) &&
      FeatureFlag.vexi.enabled_or_raise?(:active_job_skip_enqueue, job.job_class_actor) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
      GitHub.dogstats.increment("active_job.enqueue_skipped", tags: job.all_stats_tags)
      next
    end

    # Traffic mirroring
    # Refuse to queue jobs in shadow-lab (we don't want side-effects)
    # Note: this does not apply to `perform_all_later` which bypasses `around_enqueue`
    if GitHub.shadow_lab?
      GitHub.logger.info(
        "Refusing to enqueue job in shadow-lab",
        "gh.job.name" => self.class.name
      )
      next
    end

    block.call
  rescue => e # rubocop:todo Lint/RescueException
    instrument_enqueue_error!(e) unless handler_for_rescue(e)
    raise
  end

  around_perform do |_job, block|
    class_name = self.class.name.underscore
    GitHub.context.push(remote_call_source_datadog_tags: [
      "source_type:job",
      "job:#{class_name}",
      "source:job-#{class_name}",
    ])

    block.call

    GitHub.context.pop_key(:remote_call_source_datadog_tags)
  end

  # important that this is the outermost around_perform block
  around_perform do |_job, block|
    GH::Context.enabled(&block)
  end

  around_perform do |_job, block|
    with_logging_contexts(&block)
  end

  around_perform do |_job, block|
    with_package_context(&block)
  end

  # The backend used to enqueue the job. Purely informational and only used in metrics.
  attr_accessor :enqueue_backend

  # Adds an optional TTL in seconds to a job. If the TTL expires before a worker dequeues
  # the job, it will be dropped. Example usage:
  #
  #   MyJob.set(ttl: 5.minutes).perform_later
  attr_accessor :ttl

  def self.perform_enqueued_jobs?
    # internal way ActiveJob's :test adapter knows to perform_now
    # (rails's RockQueue.inline {})
    queue_adapter.respond_to?(:perform_enqueued_jobs) && queue_adapter.perform_enqueued_jobs
  end

  # Public: Inspect the currently enqueued jobs for a job class. If there are multiple job classes
  # enqueued to the same queue, it's possible that `peek` will return empty results even though
  # jobs exists due to job class filtering. To avoid false negatives for jobs on shared queues,
  # consider using a larger `limit` param.
  #
  # Returns an Array of ActiveJob instances.
  def self.peek(limit: 1, queue: nil)
    return [] unless queue_adapter.respond_to?(:peek)

    queue_adapter
      .peek(queue: queue || class_queue_name, limit: limit)
      .select { |klass| klass.instance_of?(self) }
      .take(limit)
  end

  # Public: Inspect jobs that are currently being processed.
  #
  # Returns an Array of ActiveJob instances.
  def self.in_progress(queue: nil)
    return [] unless queue_adapter.respond_to?(:in_progress)

    queue_adapter
      .in_progress(queue: queue || class_queue_name)
      .select { |klass| klass.instance_of?(self) }
  end

  # Public: Query the number of enqueued jobs.
  #
  # Returns an Integer.
  def self.queue_depth(queue: nil)
    return 0 unless queue_adapter.respond_to?(:queue_depth)

    queue_adapter.queue_depth(queue: queue || class_queue_name)
  end

  # Internal: Attempt to derive the queue name at the class level. May not be accurate for jobs that
  # generate the queue name from job args.
  def self.class_queue_name
    queue_name.is_a?(Proc) ? default_queue_name : queue_name
  end

  # Public: Enqueue this job to run only _once_ during the specified interval -
  # either at the beginning or the end of that interval
  #
  # I.e. if you enqueue 10 jobs with the same `unique_id` at the same
  # time, only _the first_ job will be ran at the end of the interval
  #
  # This is useful to throttle jobs that can be "abused" by user actions;
  # if an user performs 10 pushes in 10 seconds, and there is an expensive
  # operation we want to perform "on push", using this helper method will
  # ensure that the operation only runs once.
  #
  # The interval begins when the first unique job--identified by an optional
  # unique id or its arguments--is queued. Part of a job's identifier is the
  # size of the interval, not a specific rounded deterministic time value.
  # This means if a job is supposed to have been re-queued but hasn't
  # yet, this method will prevent a new copy of the job from being added even
  # though the previous time window has passed.
  #
  # args                         - An Array of arguments with which to enqueue the job.
  # kwargs                       - A Hash of keyword arguments with which to enqueue the job.
  # interval                     - An optional Integer interval in seconds during which we'll
  #                                deduplicate the job. Defaults to 60 seconds.
  # run_at_beginning_of_interval - Queue the job at the beginning of the interval instead of at the end. Defaults to false.
  # unique_id                    - An optional String value that uniquely identifies this job for
  #                                deduplication, preventing the same job from running more than
  #                                once during the interval. Defaults to a String representation
  #                                of the job's arguments.
  # additional_tags              - array of additional tags to include in metrics
  #
  # Returns true if job was enqueued, false if not.
  def self.enqueue_once_per_interval(args: [], kwargs: {}, interval: 60, run_at_beginning_of_interval: false, unique_id: nil, additional_tags: [])
    unless args.is_a?(Array)
      raise ArgumentError, "args must be an Array"
    end
    unless kwargs.is_a?(Hash) || kwargs.is_a?(HashWithIndifferentAccess)
      raise ArgumentError, "kwargs must be a Hash"
    end
    class_name = self.name.underscore
    tags = ["class:#{class_name}"] + additional_tags

    if interval.zero?
      GitHub.dogstats.increment("job.once_per_interval.zero_interval", tags: tags)
      perform_later(*args, **kwargs)
      return true
    end

    unique_id ||= generate_unique_id(args, kwargs)
    cache_key = "job:once_per_interval:#{class_name}:#{interval}:#{unique_id}"

    # EX seconds -- Set the specified expire time, in seconds.
    # NX -- Only set the key if it does not already exist.
    if GitHub.legacy_redis.set(cache_key, 1, nx: true, ex: interval.to_i)
      GitHub.dogstats.increment("job.once_per_interval.queued", tags: tags)
      if run_at_beginning_of_interval
        perform_later(*args, **kwargs)
      else
        set(wait: interval.seconds).perform_later(*args, **kwargs)
      end
      true
    else
      GitHub.dogstats.increment("job.once_per_interval.duplicate", tags: tags)
      false
    end
  end

  # Helper for jobs that are confirmed idempotent and safe to retry on worker shutdown
  def self.retry_on_dirty_exit
    retry_on Aqueduct::Worker::JobKilled do |job, error|
      if block_given?
        yield(job, error)
      else
        raise error
      end
    end
  end

  # Helper to retry on "expected" exceptions where the db or other dependency is down, from lib/resiliency/response.rb
  def self.retry_on_recoverable_exceptions(wait: :polynomially_longer, attempts: 5)
    Resiliency::Response::UnavailableExceptions.each do |error_class|
      retry_on error_class, wait: wait, attempts: attempts do |job, error|
        if block_given?
          yield(job, error)
        else
          raise error
        end
      end
    end
  end

  # Public: Is this job class eligible for async enqueues as a last resort?
  #
  # In rare circumstances, the job adapter may decide to enqueue a job asynchronously. This can
  # happen if multiple enqueue attempts fail or if a request enqueues jobs so heavily that waiting
  # for all individual enqueues to complete risks timing out the request.
  #
  # In async mode, the caller cannot know if the job enqueue succeeded and it's possible that an
  # unexpected non-graceful unicorn shutdown could lose the job. For most jobs, this is the desired
  # behavior: attempt to complete the enqueue by any means necessary. However, job classes that
  # absolutely *must* have an enqueue acknowledgement for data integrity reasons and would prefer
  # an exception to an asynchronous enqueue attempt can override this method to return false.
  def self.allow_async_enqueues?
    true
  end

  def self.redeliver_after(timeout)
    @redelivery_timeout = timeout
  end

  def self.redelivery_timeout
    @redelivery_timeout
  end

  def redelivery_timeout
    self.class.redelivery_timeout
  end

  # This excludes the original delivery. Setting this to 2 will allow Aqueduct to deliver a job up to 3 times in total.
  # This is because the first delivery doesn't count as a re-delivery.
  #
  # This setting only applies to jobs that are either lost while in transit to the worker or jobs don't finish
  # executing gracefully (Due to a hard shutdown for instance). This timeout does not apply to jobs that throw an
  # uncaught exception.
  #
  # Ordinarily, there should be no need to change this setting.
  def self.set_max_redelivery_attempts(attempts)
    @max_redelivery_attempts = attempts
  end

  def self.max_redelivery_attempts
    @max_redelivery_attempts
  end

  def max_redelivery_attempts
    self.class.max_redelivery_attempts
  end

  # Automatically retry when throttler errors are encountered.
  retry_on Freno::Throttler::Error, wait: :polynomially_longer, attempts: 10

  def all_stats_tags(error: $!, attempt_number: 0)
    [
      "catalog_service:#{logical_service}",
      "class:#{self.class.name.underscore}",
      "queue:#{queue_name}",
      "adapter:#{self.class.queue_adapter_name}",
      error ? "error:#{error.class.to_s.underscore}" : nil, # to_s accounts for anonymous classes
      ("attempt_number:#{attempt_number}" if attempt_number > 0),
      ("backend:#{enqueue_backend}" if enqueue_backend),
      ("worker_pool:#{worker_pool}" unless worker_pool.blank?),
      "scheduled:#{self._scheduled_interval ? "true" : "false"}",
    ].concat(stats_tags).compact
  end

  # For use with feature flags
  def self.job_class_actor
    ActiveJob::JobClassActor.new(self)
  end

  def job_class_actor
    self.class.job_class_actor
  end

  def set(options = {})
    self.ttl = options[:ttl] if options[:ttl]
    super
  end

  def _perform_job
    if Rails.env.test? # rubocop:disable GitHub/DoNotBranchOnRailsEnv
      ActiveSupport::ExecutionContext.set(job: self) do
        super
      end
    else
      super
    end
  end

  def perform_now(*args)
    super
  rescue Aqueduct::Worker::JobKilled => e
    GitHub.dogstats.increment("job.job_killed", tags: all_stats_tags)
    instrument_error!(e)
    rescue_with_handler(e) || raise
  rescue GitHub::Restraint::UnableToLock
    # Rescue here so that the job has had a chance to retry the prescribed number of times,
    # when applicable.
    GitHub.dogstats.increment("active_job.unable_to_lock", tags: all_stats_tags)
  rescue Exception => e # rubocop:todo Lint/RescueException
    instrument_error!(e)
    raise
  end

  private_class_method def self.generate_unique_id(args, kwargs)
    args_key = args.join(":")
    kwargs_key = kwargs.map { |k, v| "#{k}=#{v}" }.join(":")
    if args_key.empty?
      kwargs_key
    elsif kwargs_key.empty?
      args_key
    else
      "#{args_key}:#{kwargs_key}"
    end
  end

  protected

  # Override this in your job if you'd like to include custom tags
  def stats_tags
    []
  end

  # Override this in your job to add the provided data to the logging context
  def logging_context
    hsh = {
      "gh.job.active_job_id" => job_id,
      "gh.job.aqueduct_id" => GitHub.context[:aqueduct_job_id],
    }
    hsh.merge!(GitHub::CurrentTenant.logging_context) if log_tenant_context?
    hsh
  end

  def log_tenant_context?
    GitHub.multi_tenant_enterprise? && FeatureFlag.vexi.enabled_or_raise?(:tenant_context_telemetry_background_jobs_splunk) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
  end

  # Override this in your job to add the provided data to the failbot context
  # NOTE: arguments are not allowed keys so their potentially sensitive data
  # should not be at risk on dotcom.
  def failbot_context
    { arguments: arguments.inspect, active_job_class: self.class.name }
  end

  def use_mysql1_replica
    if ActiveRecord::Base.single_database_cluster?
      yield
    else
      # rubocop:todo GitHub/OnlyCallConnectedToOnActiveRecordBase
      ApplicationRecord::Mysql1.connected_to(role: :reading) do
        yield
      end
      # rubocop:enable GitHub/OnlyCallConnectedToOnActiveRecordBase
    end
  end

  private

  # The currently configured worker pool for use in stats, if configured.
  def worker_pool
    Aqueduct::Worker.config.worker_pool
  end

  def instrument_job(name, error: nil, on: nil)
    GitHub.instrument("#{name}.active_job", { job: self, error: error, on: on }.compact) do |*args|
      yield(*args) if block_given?
    end
  end

  def instrument_enqueue_error!(error)
    instrument_job("error", error: error, on: :enqueue) do |_payload|
      raise # allow ActiveSupport::Notifications to add exception to payload
    end
  end

  def instrument_error!(error)
    instrument_job("error", error: error, on: :perform) do |_payload|
      raise # allow ActiveSupport::Notifications to add exception to payload
    end
  end

  def record_error(error)
    GitHub.dogstats.increment("active_job.error", tags: all_stats_tags(error: error))
  end

  def with_logging_contexts(&block)
    # The important stuff, this can't be overridden. The job is set in the worker but there
    # should be no harm setting it here as well.
    base_log_context = { "gh.job.name" => self.class.name }

    Failbot.push(base_log_context.reverse_merge(failbot_context))

    push_service_mapping_context do
      GitHub.logger.with_named_tags(base_log_context.reverse_merge(logging_context), &block)
    end
  end

  def with_package_context(&block)
    return yield if GitHub.packageowners.strict_queries?(GitHub.packageowners.package_for_type(self.class))
    GitHub::DomainIsolation.within_domain_of(self.class, &block)
  end
end
