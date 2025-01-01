# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: false
# frozen_string_literal: true

require "active_job/job_class_actor"

# Base class for hydro message jobs produced by the Aqueduct bridge.
class HydroMessageJob
  include ActiveSupport::Rescuable
  include ActiveSupport::Callbacks
  include GitHub::ServiceMapping

  define_callbacks :perform

  set_callback :perform, :around, :with_remote_call_source_datadog_tags
  set_callback :perform, :around, :select_default_database
  set_callback :perform, :around, :with_span
  # with_logging_contexts should come after with_span to ensure that we push service mapping onto the containing span
  set_callback :perform, :around, :with_logging_contexts
  set_callback :perform, :around, :with_package_context
  set_callback :perform, :around, :with_gh_context


  # We need to include this module here so that the `set_callback`s in `TenantContext::HydroMessageJobTenantContext` are called in the right order
  include TenantContext::HydroMessageJobTenantContext

  MAX_REPLICATION_DELAY_WAIT_SECONDS = 2

  DEFAULT_MAX_RETRIES = 5
  DEFAULT_DELAY = 3.seconds
  DEFAULT_JITTER = 0.15

  # errors - An array of errors to retry on
  # delay - Re-enqueues the job with a delay specified either in seconds (default: 3 seconds), or as a symbol
  #   reference of :polynomially_longer
  # max_retries - Re-enqueues the job the specified number of times (default: 5 attempts) or a symbol reference
  #   of :unlimited to retry the job until it succeeds
  # jitter - A random delay of wait time used when calculating backoff. The default is 15% (0.15) which represents the
  #   upper bound of possible wait time (expressed as a percentage)
  def self.retry_on(*errors, delay: DEFAULT_DELAY, max_retries: DEFAULT_MAX_RETRIES, jitter: DEFAULT_JITTER)
    rescue_from(*errors) do |exception|
      attempts = retries(exception)
      if max_retries == :unlimited || attempts < max_retries
        if GitHub.flipper[:do_not_rename_delay_in_hydro_retry_on].enabled?
          if delay == :polynomially_longer
            seconds_to_wait = ((attempts**4) + (Kernel.rand * (attempts**4) * jitter)) + 2
          else
            seconds_to_wait = delay
          end
          GitHub.dogstats.increment("github.hydro_message_job.retried", tags: all_stats_tags)
          self.retry(exception, delay: seconds_to_wait)
        else
          if delay == :polynomially_longer
            delay = ((attempts**4) + (Kernel.rand * (attempts**4) * jitter)) + 2
          end
          GitHub.dogstats.increment("github.hydro_message_job.retried", tags: all_stats_tags)
          self.retry(exception, delay: delay)
        end
      else
        GitHub.dogstats.increment("github.hydro_message_job.error", tags: all_stats_tags)
        if block_given?
          yield self, exception
        else
          raise exception
        end
      end
    end
  end

  def self.retry_on_dirty_exit
    retry_on Aqueduct::Worker::JobKilled
  end

  def self.discard_on(*errors)
    rescue_from(*errors) do
      GitHub.dogstats.increment("github.hydro_message_job.discarded", tags: all_stats_tags)
      yield($!) if block_given?
      true
    end
  end

  class_attribute :queue_name, instance_writer: false
  class_attribute :primary_clusters

  def self.queue_as(queue_name)
    self.queue_name = queue_name
  end

  class UnknownHydroMessageJobError < StandardError
    def initialize(queue_name)
      super "could not find a HydroMessageJob for queue '#{queue_name}'"
    end
  end

  def self.class_for_queue(queue_name)
    # explicit mapping first, if job classes are loaded (they are in production).
    # Otherwise assume an implicit mapping: hydro_octochat_login -> HydroOctochatLoginJob
    job_class = begin
      descendants.detect { |d| d.queue_name.to_s == queue_name.to_s } ||
      (queue_name.camelize + "Job").safe_constantize
    end

    # If we still didn't find a matching class, the service may have jobs nested under
    # a namespace module. These follow a convention, so with a little string manipulation
    # we can still find the matching class for a queue name.
    # This is only needed in development and test, since in production all jobs are eager loaded.
    if Rails.env.development? || Rails.env.test? # rubocop:disable GitHub/DoNotBranchOnRailsEnv
      job_class ||= begin
        match = nil

        [
          # security overview analytics
          "security_overview_analytics",
          # security products
          "advanced_security",
          "code_scanning",
          "repository_vulnerability_alert",
          "security_center",
          "security_products_enablement",
        ].detect do |namespace|
          # e.g. "hydro_<service>_repository_pushed_job" -> "<service>/hydro_repository_pushed_job"
          match = "#{namespace}/#{queue_name.sub("#{namespace}_", "")}_job".camelize.safe_constantize
        end

        match
      end
    end

    if job_class.nil?
      raise UnknownHydroMessageJobError, queue_name
    end
    job_class
  end

  retry_on WaitForReplication::DataUnavailable, max_retries: :unlimited

  def self.use_primaries(*clusters)
    self.primary_clusters ||= []
    self.primary_clusters.concat(clusters)
  end

  def self.default_to_write_connection!
    @default_to_write_connection = true
  end

  def self.default_to_write_connection?
    @default_to_write_connection ||
      GitHub.flipper[:hydro_message_job_default_to_write_connection].enabled?(job_class_actor) ||
      # GHES & Proxima have only one write cluster.
      # So use the write connection if the job indicates it may need a primary connection.
      (ActiveRecord::Base.single_database_cluster? && self.primary_clusters)
  end

  # For use with feature flags
  def self.job_class_actor
    ActiveJob::JobClassActor.new(self)
  end

  attr_reader :protobuf, :headers
  attr_reader :queue
  attr_reader :topic, :partition, :offset, :schema, :timestamp, :timestamp_nano
  attr_reader :message
  attr_accessor :started_waiting_at

  def initialize(protobuf:, headers:, schema:, timestamp:, timestamp_nano:, message:, queue:)
    @protobuf = protobuf
    @headers = headers
    @topic = headers["topic"]
    @partition = headers["partition"]&.to_i
    @offset = headers["offset"]&.to_i
    @schema = schema
    @timestamp = timestamp
    @timestamp_nano = timestamp_nano
    @message = message
    @queue = queue
  end

  # Internal: perform a hydro message job, rescuing from errors with configured handlers
  def perform_now
    run_callbacks :perform do
      perform
    end
  rescue Exception => exception # rubocop:todo Lint/GenericRescue
    handler = rescue_with_handler(exception)
    unless handler
      GitHub.dogstats.increment("github.hydro_message_job.error", tags: all_stats_tags)
      raise
    end
  end

  def perform
    raise NotImplementedError
  end

  def retry(exception, delay: DEFAULT_DELAY)
    attempts = JSON.parse(headers.fetch("retries", "{}"))
    attempts[exception.class.name] ||= 0
    attempts[exception.class.name] += 1

    updated = headers.merge("retries" => attempts.to_json)
    deliver_at = delay > 0 ? Time.now + delay : nil
    GitHub::Aqueduct::HydroMessageJobContext.enqueue_hydro_message_job(protobuf, queue: queue, headers: updated, deliver_at: deliver_at)
  end

  def retries(exception)
    attempts = JSON.parse(headers.fetch("retries", "{}"))
    attempts.fetch(exception.class.name, 0)
  end

  # Returns the number of executions for the job, similar to ActiveJob#executions
  def executions
    attempts_by_exception = JSON.parse(headers.fetch("retries", "{}"))
    attempts_by_exception.values.sum + 1
  end

  def all_stats_tags(error: $!)
    tags = [
      "catalog_service:#{logical_service}",
      "class:#{self.class.name.underscore}",
      "queue:#{queue}",
      "topic:#{topic}",
    ]
    tags << "error:#{error.class.name.underscore}" if error

    tags
  end

  private

  def select_default_database(&block)
    DatabaseSelector.instance.track_writes(DatabaseSelector::LastOperations.from_hydro_message_job(self)) do
      if self.class.default_to_write_connection?
        track_database_selection(:primary)
        with_write(&block)
      elsif self.class.primary_clusters
        track_database_selection(:mixed)

        with_read do
          wait_for_replication
          with_primaries do
            block.call
          end
        end
      else
        track_database_selection(:replica)

        with_read do
          wait_for_replication
          block.call
        end
      end
    end
  end

  def wait_for_replication
    self.started_waiting_at ||= Time.current
    WaitForReplication.new(
      DatabaseSelector::ReplicationState.current.to_hash,
      max_wait_seconds: MAX_REPLICATION_DELAY_WAIT_SECONDS,
      job_name: self.class.name,
    ).wait!

    GitHub.dogstats.distribution(
      "github.hydro_message_job.replication_wait_ms",
      (Time.current - started_waiting_at) * 1000,
      tags: all_stats_tags
    )
  end

  def with_read(&block)
    ActiveRecord::Base.connected_to(role: :reading, &block)
  end

  def with_primaries(primaries = nil, &block)
    if ActiveRecord::Base.single_database_cluster?
      return with_write(&block)
    end

    primaries ||= self.class.primary_clusters
    flag_name = "#{self.class.name.gsub(":", "_")}_primaries"

    unless GitHub.flipper[flag_name].off?
      GitHub.schema_cached_models.select do |klass|
        actor = ClusterAsActor.new(klass.name)
        if GitHub.flipper[flag_name].enabled?(actor)
          primaries |= [klass]
        end
      end
    end
    ActiveRecord::Base.connected_to_many(primaries, role: :writing, &block)
  end

  def with_write(&block)
    ActiveRecord::Base.connected_to(role: :writing, &block)
  end

  def track_database_selection(type)
    GitHub.dogstats.increment("github.hydro_message_job.database_selected", tags: all_stats_tags.concat(["type:#{type}"]))
  end

  def with_remote_call_source_datadog_tags(&block)
    class_name = self.class.name.underscore
    GitHub.context.push(remote_call_source_datadog_tags: [
      "source_type:job",
      "job:#{class_name}",
      "source:job-#{class_name}",
    ])

    block.call

    GitHub.context.pop_key(:remote_call_source_datadog_tags)
  end

  def with_logging_contexts(&block)
    base_log_context = {
      job: self.class.name,
      "gh.job.name": self.class.name,
    }

    Failbot.push(base_log_context.reverse_merge(failbot_log_context))

    push_service_mapping_context do
      # Logging contexts are required to be scoped and only apply within that scope.
      GitHub.logger.with_named_tags(base_log_context.reverse_merge(logging_context), &block)
    end
  end

  def with_span(&block)
    tracer = GitHub::Telemetry.tracer("hydro.consumer")
    tracer.in_span("#{queue} process",
      kind: :consumer,
      attributes: {
        "messaging.destination" => queue.to_s,
        "code.namespace" => self.class.name,
        "messaging.system" => "aqueduct",
        "messaging.message.id" => GitHub.context[:aqueduct_job_id] || ""
      },
    &block)
  end

  def with_package_context(&block)
    return yield if GitHub.packageowners.strict_queries?(GitHub.packageowners.package_for_type(self.class))
    GitHub::DomainIsolation.within_domain_of(self.class, &block)
  end

  def with_gh_context(&block)
    GH::Context.enabled(&block)
  end

  # Override this in your job to add the provided data to the failbot context
  # NOTE: arguments are not allowed keys so their potentially sensitive data
  # should not be at risk on dotcom.
  def failbot_log_context
    { arguments: message.inspect, active_job_class: self.class.name }
  end

  # Override this in your job to add the provided data to the logging context
  def logging_context
    {
      "gh.job.aqueduct_id" => GitHub.context[:aqueduct_job_id],
    }
  end

end
