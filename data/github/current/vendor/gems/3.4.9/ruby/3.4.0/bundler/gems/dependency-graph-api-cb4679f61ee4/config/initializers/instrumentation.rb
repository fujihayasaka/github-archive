# frozen_string_literal: true
require "instrumentor"
require "dependency_graph/sql_utils/stack_filter"
require "dependency_graph/sql_utils/sql_digester"

# A global singleton Instrument is available everywhere
Instrument = Instrumentor.new(Rails.application.stats)

def stats
  Rails.application.stats
end

def hash_to_tags(hash)
  hash.map { |k, v| [k, v].join(":") }
end

def job_tags(payload)
  job = payload[:job]
  tags = []
  tags << "adapter:#{payload[:adapter].class.name.demodulize.remove('Adapter').underscore}" if payload.has_key?(:adapter)
  tags << "error:#{payload[:error].class}" if payload.has_key?(:error)
  tags << "on:#{payload[:on]}" if payload.has_key?(:on)
  tags.concat(job.all_stats_tags)
end

def query_logging_enabled?
  return ENV.fetch("DG_NORMALIZED_QUERY_LOGGING", "false") == "true"
end

# Hooks from  Action Controller

ActiveSupport::Notifications.subscribe("process_action.action_controller") do |name, start, finish, id, payload|
  duration_ms = (finish - start) * 1000

  tag_hash = payload.slice(:controller, :action, :status)
  tag_hash[:query_type] = payload[:headers]["X-GitHub-DepGraph-Query-Type"] || "unknown"
  tag_hash[:user_type] = payload[:headers]["GitHub-DepGraph-User-Type"] || "unknown"
  tags = hash_to_tags(tag_hash)

  stats.increment("action_controller.request", {
    tags: tags
  })
  stats.distribution("action_controller.request.dist.time", duration_ms, {
    tags: tags
  })

  if db_runtime_ms = payload[:db_runtime]
    stats.distribution("action_controller.request.dist.time.db", db_runtime_ms, {
      tags: tags
    })
  end
end

# Hooks from Active Record

ActiveSupport::Notifications.subscribe("sql.active_record") do |name, start, finish, id, payload|
  sql = payload[:sql]
  unless payload[:name] == "SCHEMA" || sql.blank?

    # When logging is enabled, dump query digests and backtraces to Splunk for queries against "dg_manifest_dependencies"
    if query_logging_enabled? && sql.include?("dg_manifest_dependencies")
      source_frame = DependencyGraph::SqlUtils::StackFilter.first_significant_frame(caller)
      query_digest = DependencyGraph::SqlUtils::SqlDigester.digest_sql(sql)

      DependencyGraph.logger.info("Query containing dg_manifest_dependencies",
        "code.function": source_frame,
        "sql.query": query_digest
      )
    end

    duration_ms = (finish - start) * 1000

    begin
      action = sql.split(" ", 2).first.downcase
    rescue
      # don't fail if we can't parse the query
      action = ""
    end
    unless action.in?(["select", "insert", "update", "delete", "begin", "commit"])
      action = "unknown"
    end

    tags = hash_to_tags({
      operation: action,
      host: payload[:connection_url],
      name: payload[:name],
    })

    stats.timing("sql.runtime.total", duration_ms, {
      tags: tags
    })
    stats.distribution("sql.dist.time", duration_ms, {
      tags: tags
    })
  end
end

# Hooks from GraphQLTimer (lib/graphql_timer.rb)
# TODO: port this to our Instrument framework

ActiveSupport::Notifications.subscribe("graphql.query.started") do |name, start, finish, id, payload|
  query = payload[:query]

  tags = hash_to_tags({
    mutation: query.mutation?,
    operation_name: query.operation_name,
    valid: query.valid?,
  })

  stats.increment("graphql.query.abandoned", tags: tags)
end

ActiveSupport::Notifications.subscribe("graphql.query.finished") do |name, start, finish, id, payload|
  query = payload[:query]

  tags = hash_to_tags({
    mutation: query.mutation?,
    operation_name: query.operation_name,
    valid: query.valid?,
  })

  stats.decrement("graphql.query.abandoned", tags: tags)
end

ActiveSupport::Notifications.subscribe("graphql.query.time") do |name, start, finish, id, payload|
  duration_ms = payload[:duration] * 1000
  query       = payload[:query]

  tags = hash_to_tags({
    mutation: query.mutation?,
    operation_name: query.operation_name,
    valid: query.valid?,
  })

  stats.timing("graphql.query.time", duration_ms, tags: tags)
end

ActiveSupport::Notifications.subscribe("graphql.field.time") do |name, start, finish, id, payload|
  duration_ms = payload[:duration] * 1000
  field       = payload[:field]
  type        = payload[:type]

  # dont instrument instropection queries
  unless type.name.starts_with?("__")
    tags = hash_to_tags({
      field: field.name,
      mutation: !!field.mutation,
      type: type.name,
    })
    # Timing metric is deprecated, will be removed.
    stats.timing("graphql.field.time", duration_ms, tags: tags)
    stats.distribution("graphql.field.dist.time", duration_ms, tags: tags)
  end
end

ActiveSupport::Notifications.subscribe("enqueue.active_job") do |_, _, _, _, payload|
  stats.increment("active_job.enqueued", tags: job_tags(payload))
end

ActiveSupport::Notifications.subscribe("perform_start.active_job") do |_, _, _, _, payload|
  stats.increment("active_job.performed", tags: job_tags(payload))
end

ActiveSupport::Notifications.subscribe("perform.active_job") do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  stats.distribution("active_job.perform.dist.time", event.duration, tags: job_tags(event.payload))
end

ActiveSupport::Notifications.subscribe("discard.active_job") do |_, _, _, _, payload|
  stats.increment("active_job.discard", tags: job_tags(payload))
end

ActiveSupport::Notifications.subscribe("enqueue_retry.active_job") do |_, _, _, _, payload|
  stats.increment("active_job.retry", tags: job_tags(payload))
end

ActiveSupport::Notifications.subscribe("retry_stopped.active_job") do |_, _, _, _, payload|
  stats.increment("active_job.stop_retry", tags: job_tags(payload))
end

ActiveSupport::Notifications.subscribe("error.active_job") do |_, _, _, _, payload|
  stats.increment("active_job.error", tags: job_tags(payload))
end

# Circuit breaker instrumentation
# See github/github:
# https://github.com/github/github/blob/28c6b6e7ad9a4e3113e42aafca7d09300bf5a3b9/config/instrumentation/resilient.rb#L3

ActiveSupport::Notifications.subscribe "resilient.circuit_breaker.allow_request" do |_name, start, ending, _transaction_id, payload|
  if key = payload[:key]
    stats.distribution("resilient.circuit_breaker.allow_request.dist.time", (ending - start) * 1_000, tags: ["key:#{key.name}"])

    if payload[:force_closed]
      stats.increment("resilient.circuit_breaker.force_closed", tags: ["key:#{key.name}"])
    end

    if payload[:force_open]
      stats.increment("resilient.circuit_breaker.force_open", tags: ["key:#{key.name}"])
    end

    if payload[:result]
      stats.increment("resilient.circuit_breaker.allowed", tags: ["key:#{key.name}"])
    else
      stats.increment("resilient.circuit_breaker.rejected", tags: ["key:#{key.name}"])
    end
  end
end

ActiveSupport::Notifications.subscribe "resilient.circuit_breaker.open" do |_name, _start, _ending, _transaction_id, payload|
  if key = payload[:key]
    if payload[:result]
      stats.increment("resilient.circuit_breaker.open", tags: ["key:#{key.name}"])
    end
  end
end

ActiveSupport::Notifications.subscribe "resilient.circuit_breaker.allow_single_request" do |_name, _start, _ending, _transaction_id, payload|
  if key = payload[:key]
    if payload[:result]
      stats.increment("resilient.circuit_breaker.allow_single_request", tags: ["key:#{key.name}"])
    else
      stats.increment("resilient.circuit_breaker.deny_single_request", tags: ["key:#{key.name}"])
    end
  end
end

ActiveSupport::Notifications.subscribe "resilient.circuit_breaker.success" do |_name, _start, _ending, _transaction_id, payload|
  if key = payload[:key]
    stats.increment("resilient.circuit_breaker.success", tags: ["key:#{key.name}"])

    # this only happens if the circuit was open and mark success closed it;
    # shows us that circuits are correctly being closed
    if payload[:closed_the_circuit]
      stats.increment("resilient.circuit_breaker.success.closed_the_circuit", tags: ["key:#{key.name}"])
    end
  end
end

ActiveSupport::Notifications.subscribe "resilient.circuit_breaker.failure" do |_name, _start, _ending, _transaction_id, payload|
  if key = payload[:key]
    stats.increment("resilient.circuit_breaker.failure", tags: ["key:#{key.name}"])
  end
end

# Freno instrumentation
# Loosely based on the README: https://github.com/github/freno-client
# This should just report all events as a distribution metric. More specificity can be added if necessary.
ActiveSupport::Notifications.subscribe /throttler\.*/ do |name, start, finish, _id, payload|
  cluster_names = payload[:store_names] || []
  cluster_tags = cluster_names.map { |cluster_name| "cluster:#{cluster_name}" }
  stats.distribution(name, (finish - start) * 1_000, tags: cluster_tags)
end
