# typed: true
# frozen_string_literal: true

class DeliverHookEventJob < ApplicationJob
  # Although we are setting `default_to_write_connection!` this job does not
  # actually default to using write connections. This is only set because
  # this job uses custom logic for waiting for replication and removing this
  # would cause us to use the default replication wait strategy.
  default_to_write_connection! # rubocop:todo GitHub/JobsDoNotDefaultToWriteConnection

  include Hookshot::DeliverJobLogger

  MAX_REPLICATION_WAIT_TIME_SECONDS = 5

  queue_as :deliver_hook_event

  retry_on StandardError, wait: :polynomially_longer

  retry_on_dirty_exit

  def default_log_context
    @default_log_context ||= {
      "code.filepath" => "app/jobs/deliver_hook_event_job.rb",
      "gh.catalog_service" => "github/webhooks",
      "gh.request_id" => GitHub.context[:request_id]
    }
  end

  def perform(event_type, event_attributes = {})
    event_type_tag = GitHub::TaggingHelper.hook_event_type_tag_value(event_type)
    GitHub.tracer.in_span("job.#{self.queue_name}.perform", kind: :internal,
      attributes: {
        "gh.webhook.component" => "jobs",
        "gh.webhook.event_type" => event_type_tag,
      }) do |_span|
        ActiveRecord::Base.connected_to(role: :reading) { send_hooks(event_type, event_attributes) }
      end
  end


  private

  def send_hooks(event_type, event_attributes = {})
    log_context = self.default_log_context.merge({
      "code.namespace" => "DeliverHookEventJob",
      "code.function" => "send_hooks",
      "gh.webhook.event_type" => event_type
    })
    # round-trip through JSON to get string keys only
    event_attributes = GitHub::JSON.parse(GitHub::JSON.encode(event_attributes))

    job_start = Time.now
    event_type_tag = GitHub::TaggingHelper.hook_event_type_tag_value(event_type)
    event = T.let(nil, T.nilable(Hook::Event))
    GitHub.tracer.in_span("job.#{self.queue_name}.for_event_type",
                            kind: :internal,
                            attributes: {
                              "component" => "jobs",
                              "hook.event_type" => event_type_tag,
                            }) do |_span|
      log_context = log_context.merge({ "gh.webhook.action" => event_attributes["action"] })
      event = Hook::Event.for_event_type(event_type, event_attributes)
    end
    action = T.must(event).action
    tags = GitHub::TaggingHelper.create_hook_event_tags(event_type, action)
    tags << "class:#{T.must(self.class.name).underscore}"

    # This is a specific timer to instrument how long after queueing the
    # job is picked up
    hydrated_at = Time.now

    queued_at = T.let(nil, T.untyped)
    result = T.let(nil, T.untyped)
    GitHub.tracer.in_span("job.#{self.queue_name}.deliver",
                          kind: :internal,
                          attributes: {
                            "component" => "jobs",
                            "hook.event" => GitHub::TaggingHelper.hook_event_tag_value(event_type, action),
                            "hook.event_type" => event_type_tag,
                          }) do |_span|
      queued_at = queued_at_time(event_attributes["queued_at"])
      try_wait_for_replication(event_type, action, tracked_replication_state, tags)

      result = T.must(event).deliver
    end

    record_mysql_metrics(tags)
    record_timing_metrics(job_start, queued_at, hydrated_at, tags)
    result

  rescue StandardError => e # rubocop:todo Lint/GenericRescue
    tags << "exception_class:#{e.class.name&.underscore}"
    GitHub.dogstats.increment("hooks.hook_event_job.error", tags: tags)
    error_report_opts = { "#event": event_type, event_attributes: event_attributes }
    case e
    when ActiveRecord::RecordNotFound
      # Queue a job to check later if the record was deleted or just
      # hasn't been committed yet. Deleted records can be ignored
      # but we need to know if there is a transactional race
      # condition.
      report_error(e, error_report_opts)
      HookDeliveryRaceConditionCheckJob.queue_from_error(e, event_type, T.must(event).attributes)
    when ::GitRPC::InvalidRepository
      # The repository has gone away before we could send the event. As we
      # needed repository data to fulfill it, we skip delivering it.
      GitHub.dogstats.increment("hooks.deliveries_repository_gone")
      report_error(e, error_report_opts)
    when Hookshot::PayloadTooLarge
      log_params = {
        error: e,
        target: (T.must(event).target_repository || T.must(event).target_organization),
      }
      log_payload_too_large_error(**log_params)
      report_error(e, error_report_opts)
    when NoMethodError
      log_no_method_error(e, event_type, action)
      report_error(e, error_report_opts)
    else
      report_error(e, error_report_opts)
      raise e
    end
  end

  def try_wait_for_replication(event_type, action, last_writes, tags)
    return 0 if GitHub.enterprise?
    # Performs a multi-cluster wait to accommodate the replication lag of the slowest
    # cluster that was previously written to. If we fail to wait, we will not retry,
    # but rather log the exception and proceed with potentially stale data.
    replica_wait_time = wait_for_replication(last_writes, event_type)
    GitHub.dogstats.distribution("job.#{self.queue_name}.replica_wait_time_ms", (replica_wait_time * 1_000), tags: tags)
    replica_wait_time
  rescue TypeError, WaitForReplication::DataUnavailable => e
    GitHub::logger.error("Failed to wait for replication. Proceeding with potentially stale data",
      self.default_log_context.merge({
        :exception => e,
        "code.function" => "try_wait_for_replication",
        "gh.webhook.event_type" => event_type,
        "gh.webhook.action" => action
      })
    )
    if e.is_a?(WaitForReplication::DataUnavailable)
      tags_with_store_name = tags
      tags_with_store_name = tags + ["store_name:#{e.store_name}"] if e.store_name.present?
      GitHub.dogstats.increment("job.#{self.queue_name}.replica_data_unavailable", tags: tags_with_store_name)
    elsif e.is_a?(TypeError)
      GitHub.dogstats.increment("job.#{self.queue_name}.last_writes_invalid", tags: tags)
    end
  end

  def wait_for_replication(last_writes, event_type)
    unless last_writes.is_a?(Hash) && last_writes.present?
      raise TypeError.new("expected a non-empty Hash for last_writes but got #{last_writes}")
    end

    last_writes = Hook::Event
      .class_for_event_type(event_type)
      .filter_last_writes(last_writes.deep_symbolize_keys)

    return if last_writes.empty?

    WaitForReplication.new(
      last_writes,
      max_wait_seconds: DeliverHookEventJob::MAX_REPLICATION_WAIT_TIME_SECONDS
    ).wait!
  end

  def queued_at_time(queued_at)
    return unless queued_at
    queued_at.kind_of?(String) ? Time.parse(queued_at) : Time.at(queued_at)
  rescue TypeError, ArgumentError => e
    report_error(e)
    nil
  end

  def record_mysql_metrics(tags)
    GitHub::MysqlInstrumenter.queries_per_type_database.each do |db_host, counts|
      counts ||= {}
      tags_with_host = tags + ["rpc_host:#{db_host}"]
      GitHub.dogstats.count("job.#{self.queue_name}.rpc.mysql.count.reads", counts[:read].to_i, tags: tags_with_host)
      GitHub.dogstats.count("job.#{self.queue_name}.rpc.mysql.count.writes", counts[:write].to_i, tags: tags_with_host)
      GitHub.dogstats.distribution("job.#{self.queue_name}.rpc.mysql.count.reads.dist", counts[:read].to_i, tags: tags_with_host)
      GitHub.dogstats.distribution("job.#{self.queue_name}.rpc.mysql.count.writes.dist", counts[:write].to_i, tags: tags_with_host)
    end
  end

  def record_timing_metrics(start, queued_at, hydrated_at, tags)
    return unless queued_at
    hook_delay_ms = (start - queued_at) * 1_000
    GitHub.dogstats.distribution("job.#{self.queue_name}.time_enqueued", hook_delay_ms, tags: tags)

    hydrate_time = (hydrated_at - start) * 1_000
    GitHub.dogstats.distribution("job.#{self.queue_name}.hydrated_time", hydrate_time, tags: tags)

    job_perform_time = T.unsafe(Time.now - start) * 1_000
    GitHub.dogstats.distribution("job.#{self.queue_name}.perform_time", job_perform_time, tags: tags)
  rescue TypeError, ArgumentError => e
    report_error(e)
  end
end
