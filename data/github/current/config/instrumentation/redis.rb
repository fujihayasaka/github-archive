# typed: true
# frozen_string_literal: true

class Redis::Client
  def self.collector
    GitHub::DataCollector::RedisInstrumenterCollector.get_instance
  end

  def self.query_time
    collector.query_time
  end

  def self.query_time=(value)
    collector.query_time = value
  end

  def self.query_count
    collector.query_count
  end

  def self.query_count=(value)
    collector.query_count = value
  end

  def self.queries
    collector.queries
  end

  def self.queries=(value)
    collector.queries = value
  end

  def self.track
    collector.track
  end

  def self.track=(value)
    collector.track = value
  end
end

module RedisInstrumentationMiddleware
  include Kernel
  extend T::Helpers

  # Regex to parse Redit host strings into cluster + mode
  # Some example host strings used at this time in production:
  #
  # db-redis-rate-limiter-00-ro.service.github.net         -> rate-limiter-00, ro
  # db-redis-copilot-production.redis.cache.windows.net    -> copilot-production, rw
  # db-redis-dotcom-staff-wus2-01.redis.cache.windows.net  -> dotcom-staff-wus2-01, rw
  # db-redis-rate-limiter-01-rw.service.github.net         -> rate-limiter-01, rw
  # db-redis-redis102-rw.service.github.net                -> redis102, rw
  # global-cache-production.service.iad.github.net         -> global-cache-production, rw
  # redis                                                  -> redis, rw

  REDIS_PREFIX = /(?:db-redis-)?/mi.freeze
  REDIS_SUFFIX = /(?:[-\w\.]*)/mi.freeze
  REDIS_CONNECTION_ROLE = /(?:-(ro|rw))?/mi.freeze
  REDIS_CLUSTER = /([\w]+(?:-[\w]+)*?)/mi.freeze
  REDIS_HOST_PATTERN = /\A#{REDIS_PREFIX}#{REDIS_CLUSTER}#{REDIS_CONNECTION_ROLE}(?:\z|\.#{REDIS_SUFFIX}\z)/i.freeze

  # 10KB
  MINIMUM_COMMAND_SIZE = 1024 * 10

  # Up to 1_000 commands when calculating the size of a command
  # can take locally ~ 60 microseconds. We want to keep safe and
  # filter out commands that are too large, despite its unlikely
  # to happen in production.
  MAX_COMMAND_LENGTH_LIMIT_FOR_SIZE_CALCULATION = 1_000

  DOT = ".".freeze
  DASH = "-".freeze

  def now
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def connect(redis_config)
    start = now
    super
  rescue StandardError => e # rubocop:todo Lint/RescueException
    stop = now
    redis_error = e
    emit_error(e, metric: "rpc.redis.connect.error", command: "connect", sample_rate: GitHub.redis_instrumentation_connect_stats_sample_rate)
    raise
  ensure
    stop ||= now
    duration = stop - start
    duration_ms = (duration * 1000).round(5)

    tags = dogstats_tags("connect", redis_error)
    GitHub.dogstats.distribution("rpc.redis.connect.dist.time", duration_ms,
      sample_rate: GitHub.redis_instrumentation_connect_stats_sample_rate,
      tags: tags)

    if Redis::Client.track
      Redis::Client.queries << EventTrace.new("(connect)", duration, nil)
    end
    Redis::Client.query_time += duration
    Redis::Client.query_count += 1
  end

  def call(cmd, redis_config)
    start = now
    super
  rescue RedisClient::TimeoutError => e
    stop = now
    redis_error = e
    # NOTE: The order of the rescue clauses is important here.
    # TimeoutError is a subclass of ConnectionError, so it must come first.
    # We actually see TimeoutError both during retries and after retries are exhausted
    # So we track this as 'rpc.redis.error'
    emit_error(e, metric: "rpc.redis.error", command: cmd)
    raise
  rescue RedisClient::ConnectionError => e
    stop = now
    redis_error = e
    # See: https://github.com/github/monolith-systems/issues/468
    # ConnectionErrors are seen before retries are exhausted, so we track them separately.
    # once retries are exhausted, we see CannotConnectError
    emit_error(e, metric: "rpc.redis.connect.error", command: cmd, sample_rate: GitHub.redis_instrumentation_connect_stats_sample_rate)
    raise
  rescue StandardError => e # rubocop:todo Lint/RescueException
    stop = now
    redis_error = e
    emit_error(e, metric: "rpc.redis.error", command: cmd)
    raise
  ensure
    stop ||= now
    duration = stop - start
    duration_ms = (duration * 1000).round(5)

    if command_name = build_command_name(cmd)
      tags = dogstats_tags(command_name, redis_error, reduced_host_tags: true, timeout_config_tags: true)
      GitHub.dogstats.distribution("rpc.redis.dist.time", duration_ms, tags: tags)

      emit_redis_command_size_metric(command_name,
        cmd,
        "rpc.redis.dist.size",
        "rpc.redis.dist.size_overflow",
      ) if redis_config.custom[:trace_command_size]
    end

    if Redis::Client.track
      Redis::Client.queries << EventTrace.new(cmd, duration, nil)
    end
    Redis::Client.query_time += duration
    Redis::Client.query_count += 1
  end

  def call_pipelined(commands, redis_config)
    start = now
    super
  rescue RedisClient::TimeoutError => e
    stop = now
    redis_error = e
    # NOTE: The order of the rescue clauses is important here.
    # TimeoutError is a subclass of ConnectionError, so it must come first.
    # We actually see TimeoutError both during retries and after retries are exhausted
    # So we track this as 'rpc.redis.error'
    emit_error(e, metric: "rpc.redis.error", command: "pipelined")
    raise
  rescue RedisClient::ConnectionError => e
    stop = now
    redis_error = e
    # See: https://github.com/github/monolith-systems/issues/468
    # ConnectionErrors are seen before retries are exhausted, so we track them separately.
    # once retries are exhausted, we see CannotConnectError
    emit_error(e, metric: "rpc.redis.connect.error", command: "pipelined", sample_rate: GitHub.redis_instrumentation_connect_stats_sample_rate)
    raise
  rescue StandardError => e # rubocop:todo Lint/RescueException
    stop = now
    redis_error = e
    emit_error(e, metric: "rpc.redis.error", command: "pipelined")
    raise
  ensure
    stop ||= now
    duration = stop - start
    duration_ms = (duration * 1000).round(5)

    tags = dogstats_tags("pipelined", redis_error, reduced_host_tags: true, timeout_config_tags: true)
    GitHub.dogstats.distribution("rpc.redis.dist.time", duration_ms, tags: tags)

    commands.each do |command|
      command_name = build_command_name(command)
      tags = dogstats_tags(command_name, redis_error)
      GitHub.dogstats.increment("rpc.redis.pipelined",
        sample_rate: GitHub.redis_instrumentation_pipeline_stats_sample_rate,
        tags: tags)

      emit_redis_command_size_metric(command_name,
        command,
        "rpc.redis.dist.pipelined_size",
        "rpc.redis.pipelined_size_overflow",
        sample_rate: GitHub.redis_instrumentation_pipeline_stats_sample_rate
      ) if redis_config.custom[:trace_command_size]
    end

    if Redis::Client.track
      Redis::Client.queries << EventTrace.new("(pipelined)", duration, commands)
    end
    Redis::Client.query_time += duration
    Redis::Client.query_count += 1
  end

  def emit_error(error, metric:, command: nil, sample_rate: 1.0)
    return unless error_final?(error)
    return unless command_name = build_command_name(command)

    tags = dogstats_tags(command_name, error)
    GitHub.dogstats.increment(metric, sample_rate: sample_rate, tags: tags)
  end

  def error_final?(error)
    # RedisClient::Error implements final? which indicates if the error is final or if there will be retries
    # For errors that do not implement final?, we assume they are final
    error.respond_to?(:final?) ? T.unsafe(error).final? : true
  end

  def build_command_name(cmd)
    command_parts = Array(cmd)
    name = command_parts.first
    if name == "evalsha"
      # return evalsha:script_sha
      return "#{name}:#{command_parts.second}"
    end
    name
  end

  def redis_client
    T.bind(self, ::RedisClient::Middlewares)
    client
  end

  def redis_host
    redis_client.host
  end

  def cluster_info
    cluster, connection_role = redis_host.match(REDIS_HOST_PATTERN)&.captures
    host, cluster, connection_role = [redis_host, cluster&.to_sym || :unknown, connection_role&.to_sym || :rw]
  end

  def dogstats_tags(operation, error = nil, reduced_host_tags: false, timeout_config_tags: false)
    host, cluster, connection_role = cluster_info

    tags = [
      "rpc_operation:#{operation}",
      "rpc_host:#{host}",
      "rpc_site:#{GitHub.site_from_host(host)}",
      "#{GitHub::TaggingHelper::CATALOG_SERVICE_TAG}:#{GitHub.context[:catalog_service] || "unknown"}",
    ]

    tags << (GitHub::DatadogTagsCache::REDIS_CLUSTER_NAMES[cluster] || "redis_cluster:#{cluster}")
    tags << (GitHub::DatadogTagsCache::REDIS_CONNECTION_ROLES[connection_role] || "connection_role:#{connection_role}")

    if error
      error_class_name = error.class.name
      tags << (GitHub::DatadogTagsCache::REDIS_ERRORS[error_class_name] || "error:#{error_class_name}")
      tags << "error_cause:#{error.cause.class.name}" if error.cause
      tags << (error_final?(error) ? "error_final_retry:true" : "error_final_retry:false")
      tags << "error_code:#{error.code}" if error.respond_to?(:code) && error.code
    end

    if reduced_host_tags
      # Pin host tag to constant value to reduce metric cardinality, and add back other useful tags
      # that were previously auto-added based on the host tag.
      tags.push(GitHub::Dogstats::DEFAULT_HOST_TAG, GitHub::TaggingHelper.stamp_tag, GitHub::TaggingHelper.site_tag)
    end

    if timeout_config_tags
      tags.push("read_timeout:#{redis_client.read_timeout}")
    end

    if GitHub.context[:remote_call_source_datadog_tags]
      tags.concat(GitHub.context[:remote_call_source_datadog_tags])
    else
      tags.push("source:unknown")
    end
  end

  def emit_redis_command_size_metric(command_name, cmd, metric, metric_overflow, sample_rate: nil)
    return unless command_name

    if FeatureFlag.vexi.enabled?(:emit_redis_command_size_metric, default: false)
      command_size = build_command_size(cmd)
      if command_size != -1 && command_size > minimum_command_size
        GitHub.dogstats.distribution(metric, command_size, tags: dogstats_tags(command_name))
      elsif command_size == -1
        GitHub.dogstats.increment(metric_overflow, tags: dogstats_tags(command_name), sample_rate: sample_rate)
      end
    end
  end

  def build_command_size(cmd)
    command_parts = Array(cmd)
    return -1 unless command_parts.length <= max_command_length_limit_for_size_calculation
    command_parts.select { |e| e.is_a?(String) }.map(&:bytesize).sum
  end

  def minimum_command_size
    return @minimum_command_size if defined?(@minimum_command_size)

    @minimum_command_size = ENV.fetch(
      "MINIMUM_COMMAND_SIZE", MINIMUM_COMMAND_SIZE
    ).to_i
  end

  def max_command_length_limit_for_size_calculation
    return @max_command_length_limit_for_size_calculation if defined?(@max_command_length_limit_for_size_calculation)

    @max_command_length_limit_for_size_calculation = ENV.fetch(
      "MAX_COMMAND_LENGTH_LIMIT_FOR_SIZE_CALCULATION", MAX_COMMAND_LENGTH_LIMIT_FOR_SIZE_CALCULATION
    ).to_i
  end
end

RedisClient.register(RedisInstrumentationMiddleware) unless GitHub::AppEnvironment.test?
