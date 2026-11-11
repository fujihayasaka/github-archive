# typed: true
# frozen_string_literal: true

class HydroWorkflowUpdateJob < HydroMessageJob # rubocop:disable GitHub/KubeJobsRetryOnDirtyExit
  include GitHub::Tracing
  include GitHub::Memoizer

  queue_as :hydro_workflow_update

  set_callback :perform, :around, :use_mysql1_replica

  UNAVAILABLE_ERRORS = [
    ActiveRecord::ConnectionNotEstablished,
    ActiveRecord::StatementInvalid,
    ActiveRecord::QueryCanceled,
    SystemCallError, # Errno::ECONNREFUSED, Errno::ECONNRESET and friends
  ]

  FRENO_ERRORS = [Freno::Throttler::Error, Freno::Error, Freno::Throttler::WaitedTooLong]
  RETRIABLE_ERRORS = UNAVAILABLE_ERRORS + FRENO_ERRORS

  # Retry indefinitely when the workers were killed
  # This is an alternative to `retry_on_dirty_exit` so the linting rule is disabled for this class
  retry_on Aqueduct::Worker::JobKilled, delay: 5.seconds, max_retries: :unlimited
  retry_on *RETRIABLE_ERRORS

  # This job needs to write to the RAC, IPR, Mysql5, and Repositories clusters
  # Due to its high volume, any waiting for replication lag slows downs jobs and consumes workers.
  # So default to a write connection to avoid waiting for replication
  default_to_write_connection! # rubocop:todo GitHub/JobsDoNotDefaultToWriteConnection

  STATS_PREFIX = T.must(self.name).underscore
  METRIC_PROCESS_UPDATE_DURATION = "#{STATS_PREFIX}.process_update_duration"
  METRIC_MESSAGE_RECEIVED = "#{STATS_PREFIX}.message_received"
  METRIC_MESSAGE_RECEIVED_LATENCY = "#{STATS_PREFIX}.message_received_latency"
  METRIC_MESSAGE_COMPLETED_LATENCY = "#{STATS_PREFIX}.message_completed_latency"
  METRIC_MESSAGE_SKIPPED = "#{STATS_PREFIX}.message_skipped"
  METRIC_MESSAGE_SUCCESS = "#{STATS_PREFIX}.message_success"
  METRIC_MESSAGE_OUT_OF_ORDER = "#{STATS_PREFIX}.message_out_of_order"
  METRIC_MESSAGE_RETRY = "#{STATS_PREFIX}.message_retry"
  METRIC_FIND_CHECK_SUITE_DURATION = "#{STATS_PREFIX}.find_check_suite_duration"
  METRIC_FIND_CHECK_RUN_DURATION = "#{STATS_PREFIX}.find_check_run_duration"

  POSTBACK_SLO_DELAY_TOLERANCE_MS = 60_000

  trace_method :perform
  trace_method :set_tenant
  trace_method :find_check_suite
  trace_method :find_check_run
  trace_method :process_update, span_attribute_extractor: -> (instance, *args, **_kwargs) { instance.trace_message_tags(args[0]) }
  trace_method :update_gate, span_attribute_extractor: -> (instance, *args, **_kwargs) { instance.trace_message_tags(args[0]) }
  trace_method :update_check_run, span_attribute_extractor: -> (instance, *args, **_kwargs) { instance.trace_message_tags(args[0]) }
  trace_method :update_check_suite, span_attribute_extractor: -> (instance, *args, **_kwargs) { instance.trace_message_tags(args[0]) }

  # More info about statuses can be found here: https://github.com/github/github/blob/c265b45c721c7147f2136e7f28c34285fef75aee/packages/checks/app/models/check_run.rb#L55-L69

  CHECK_TRANSITIONS = {
    # Not sure this ever happens in the context of a postback
    "requested" => %w[queued in_progress completed],
    "in_progress" => ["completed"],
  }

  CHECK_SUITE_TRANSITIONS = CHECK_TRANSITIONS.merge({
    "queued" => %w[in_progress completed pending],

    # This is needed for concurrency groups
    "pending" => %w[completed pending],

    # This is needed to support gated workflow runs
    "waiting" => ["completed"],
  })

  CHECK_RUN_TRANSITIONS = CHECK_TRANSITIONS.merge({
    "queued" => %w[in_progress completed queued],

    # This is needed to support partial reruns which start out as completed
    "completed" => ["completed"],

    # This is needed for concurrency groups
    "pending" => %w[in_progress completed queued],

    # This is needed to support gated workflow runs
    "waiting" => %w[in_progress completed queued],
  })

  GATE_TRANSITIONS = {
    # closed => closed is triggered by a workflow_run being cancelled
    "closed" => %w[open rejected closed],

    # The gate state is set to open directly when it is approved/rejected from the UI.
    # We, however, still get a postback for it so we're processing it to stay compatible with the GraphQL implementation.
    "open" => ["open"],
    "rejected" => %w[rejected closed],
  }

  resolve_tenant_context do |message|
    repo_id = Platform::Helpers::GlobalId.parse(message.dig(:repository_id)).id.to_i
    T.cast(Repositories.domain.by_id(repo_id), T.nilable(Repository))&.resolve_tenant # rubocop:todo GitHub/AvoidCast
  end

  def use_mysql1_replica
    # https://github.com/github/data-patterns-and-scaling/issues/5
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

  # Public: process a Hydro message
  #
  # Returns nothing
  def perform
    time_to_processing_ms = (Time.now.to_f - timestamp.to_f) * 1_000
    instrument_message_received(time_to_processing_ms)

    workflow_update = Checks::WorkflowUpdate.new(message)

    stats_tags = stats_message_tags(workflow_update)
    failbot_context = failbot_context(workflow_update)
    logger_context = logger_context(workflow_update)

    Failbot.push(failbot_context)
    GitHub.dogstats.time(METRIC_PROCESS_UPDATE_DURATION, tags: stats_tags) do
      GitHub.logger.with_named_tags(logger_context) do
        process_update(workflow_update, stats_tags)
      end
    end

    time_to_completion_ms = (Time.now.to_f - timestamp.to_f) * 1_000
    instrument_message_success(time_to_completion_ms)
  end

  # This needs to be public so the instrumentation can access it
  def trace_message_tags(workflow_update)
    tags = {
      "hydro_msg_topic" => topic || "unknown",
      "hydro_msg_partition" => partition || 0,
      "hydro_msg_offset" => offset || 0,
      "gh.actions.workflow_update.type" => workflow_update.update_type.to_s,
      "gh.repo.id" => workflow_update.repository_id,
      "gh.actions.workflow_run.id" => workflow_update.workflow_run_id,
    }

    tags["gh.check_run.id"] = workflow_update.check_run_id if workflow_update.check_run_id
    tags["gh.check_suite.id"] = workflow_update.check_suite_id if workflow_update.check_suite_id

    tags
  end

  private

  memoize def repository
    repository_id = Platform::Helpers::GlobalId.parse(message[:repository_id]).id.to_i
    with_read { Repositories.domain.by_id(repository_id) }
  end

  def process_update(workflow_update, stats_tags)
    GitHub.logger.info({ "code.namespace" => self.class.name, "code.function" => "process_update/start" })

    if repository.nil? || repository.deleted?
      return skip(workflow_update, "repository_not_found", skip_message: "Repository not found or deleted: #{workflow_update.repository_id}")
    end

    if workflow_update.gate_update?
      update_gate(workflow_update, stats_tags)
    end

    if workflow_update.check_run_update?
      update_check_run(workflow_update, stats_tags)
    end

    if workflow_update.check_suite_update?
      update_check_suite(workflow_update, stats_tags)
    end

    GitHub.logger.info({ "code.namespace" => self.class.name, "code.function" => "process_update/end" })
  end

  def update_gate(workflow_update, stats_tags)
    check_run = find_check_run(workflow_update, stats_tags)

    if check_run.nil?
      return skip(workflow_update, "check_run_not_found")
    end

    gate_request = check_run.gate_requests.find_by(gate_id: workflow_update.gate_request_update_data[:gate_id])

    if gate_request.present?
      old_state_name = gate_request.state
      new_state_name = workflow_update.gate_request_update_data[:gate_state]
      possible_new_states = GATE_TRANSITIONS.fetch(old_state_name, [])

      unless possible_new_states.include?(new_state_name)
        message = "Out of order update for gate: Cannot transition from #{old_state_name} to #{new_state_name}. Expected state to transition to #{possible_new_states}."
        return instrument_message_out_of_order(workflow_update, "gate_status", message)
      end
    end

    Checks::CreateGateRequest.call(
      check_run: check_run,
      update_properties: workflow_update.gate_request_update_data,
    )
  end

  def update_check_run(workflow_update, stats_tags)
    check_run = find_check_run(workflow_update, stats_tags)

    if check_run.nil?
      return skip(workflow_update, "check_run_not_found")
    end

    old_status_name = check_run.status
    update_data = workflow_update.check_run_update_data
    new_message_status_name = update_data.dig(:check_run_updates, :status)
    new_status_enum = CheckRun.statuses.find { |_, status_name| status_name == new_message_status_name }

    if new_status_enum.nil?
      return skip(workflow_update, "invalid_check_run_status", skip_message: "Invalid status #{new_message_status_name} for check run #{check_run.id}")
    end

    new_status_name = new_status_enum.first
    possible_new_states = CHECK_RUN_TRANSITIONS.fetch(old_status_name, [])

    unless possible_new_states.include?(new_status_name)
      message = "Out of order update for check run: Cannot transition from '#{old_status_name}' to '#{new_status_name}'. Expected state to transition to #{possible_new_states}"
      return instrument_message_out_of_order(workflow_update, "check_run_status", message)
    end

    Checks::UpdateCheckRun.call(
      check_run: check_run,
      update_properties: update_data,
    )
  end

  def update_check_suite(workflow_update, stats_tags)
    check_suite = find_check_suite(workflow_update, stats_tags)

    if check_suite.nil?
      return skip(workflow_update, "check_suite_not_found")
    end

    old_status_name = check_suite.status
    new_message_status_name = workflow_update.check_suite_update_data.dig(:check_suite_updates, :status)
    new_status_enum = CheckSuite.statuses.find { |_, status_name| status_name == new_message_status_name }

    if new_status_enum.nil?
      return skip(workflow_update, "invalid_check_suite_status", skip_message: "Invalid status #{new_message_status_name} for check suite #{check_suite.id}")
    end

    new_status_name = new_status_enum.first
    possible_new_states = CHECK_SUITE_TRANSITIONS.fetch(old_status_name, [])

    unless possible_new_states.include?(new_status_name)
      message = "Out of order update for check suite: Cannot transition from '#{old_status_name}' to '#{new_status_name}'. Expected state to transition to #{possible_new_states}"
      return instrument_message_out_of_order(workflow_update, "check_suite_status", message)
    end

    Checks::UpdateCheckSuite.call(
      check_suite: check_suite,
      update_properties: workflow_update.check_suite_update_data,
    )
  end

  def find_check_suite(workflow_update, tags)
    GitHub.dogstats.time(METRIC_FIND_CHECK_SUITE_DURATION, tags: tags) do
      CheckSuite.find_by(
        id: workflow_update.check_suite_id,
        repository_id: workflow_update.repository_id,
      )
    end
  end

  def find_check_run(workflow_update, tags)
    GitHub.dogstats.time(METRIC_FIND_CHECK_RUN_DURATION, tags: tags) do
      Checks.domain.check_runs.for_id(workflow_update.check_run_id, repository_id: workflow_update.repository_id)
    end
  end

  def skip(workflow_update, reason, skip_message: "")
    tags = ["reason:#{reason}"] + default_stats_tags
    GitHub.dogstats.increment(METRIC_MESSAGE_SKIPPED, tags: tags)

    GitHub.logger.info("skipping workflow update message", {
      "code.namespace" => self.class.name,
      "code.function" => "skip",
      "workflow_update.skip.reason" => reason,
      "workflow_update.skip.message" => skip_message
    })
  end

  def instrument_message_received(time_to_processing_ms)
    GitHub.dogstats.increment(METRIC_MESSAGE_RECEIVED, tags: default_stats_tags)
    GitHub.dogstats.timing(METRIC_MESSAGE_RECEIVED_LATENCY, time_to_processing_ms.to_i, tags: default_stats_tags)
  end

  def instrument_message_success(time_to_completion_ms)
    GitHub.dogstats.increment(METRIC_MESSAGE_SUCCESS, tags: default_stats_tags)
    if FeatureFlag.vexi.enabled_or_raise?(:actions_postback_delayed_boolean_flag) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
      GitHub.dogstats.timing(METRIC_MESSAGE_COMPLETED_LATENCY, time_to_completion_ms.to_i, tags: default_stats_tags + ["delayed:#{time_to_completion_ms.to_i > POSTBACK_SLO_DELAY_TOLERANCE_MS}"])
    else
      GitHub.dogstats.timing(METRIC_MESSAGE_COMPLETED_LATENCY, time_to_completion_ms.to_i, tags: default_stats_tags)
    end
  end

  def instrument_message_out_of_order(workflow_update, type, message)
    tags = ["type:#{type}"] + default_stats_tags
    GitHub.dogstats.increment(METRIC_MESSAGE_OUT_OF_ORDER, tags: tags)

    GitHub.logger.info("detected out of order message", {
      "code.namespace" => self.class.name,
      "code.function" => "instrument_message_out_of_order",
      "workflow_update.out_of_order.type" => type,
      "workflow_update.out_of_order.message" => message
    })
  end

  def stats_message_tags(workflow_update)
    ["update_type:#{workflow_update.update_type}"] + default_stats_tags
  end

  def default_stats_tags
    [
      "topic:#{topic}",
      "partition:#{partition}",
      "queue:#{queue}",
      "job:#{T.must(self.class.name).underscore}",
    ]
  end

  def logger_context(workflow_update)
    context = {
      "gh.hydro.msg.topic" => topic,
      "gh.hydro.msg.partition" => partition || 0,
      "gh.hydro.msg.offset" => offset || 0,
      "gh.repo.id" => workflow_update.repository_id,
      "gh.actions.workflow_run.id" => workflow_update.workflow_run_id,
      "gh.actions.workflow_update.type" => workflow_update.update_type.to_s,
    }
    context["gh.check_run.id"] = workflow_update.check_run_id if workflow_update.check_run_id
    context["gh.check_suite.id"] = workflow_update.check_suite_id if workflow_update.check_suite_id

    context
  end

  def failbot_context(workflow_update)
    # Tags are filtered before being sent to Sentry: https://github.com/github/github/blob/7506e794f09eef702c0b7a9dbd83a0e019b8255c/lib/github/failbot_key_filter.rb#L65
    context = {
      catalog_service: logical_service,
      hydro_msg_topic: topic,
      hydro_msg_partition: partition || 0,
      hydro_msg_offset: offset || 0,
      "gh.repo.id": workflow_update.repository_id,
      "gh.actions.workflow_run.id": workflow_update.workflow_run_id,
    }

    context[:"gh.check_run.id"] = workflow_update.check_run_id if workflow_update.check_run_id
    context[:"gh.check_suite.id"] = workflow_update.check_suite_id if workflow_update.check_suite_id

    context
  end

  # Override the method in the base class to add metrics
  def retry(exception, delay: DEFAULT_DELAY)
    super

    tags = ["exception:#{exception.class.name.underscore}"] + default_stats_tags
    GitHub.dogstats.increment(METRIC_MESSAGE_RETRY, tags: tags)
    GitHub.logger.error({
      "code.namespace" => self.class.name,
      "code.function" => "retry",
      "gh.hydro.msg.topic" => topic,
      "gh.hydro.msg.partition" => partition || 0,
      "gh.hydro.msg.offset" => offset || 0,
      :exception => exception,
    })
  end
end
