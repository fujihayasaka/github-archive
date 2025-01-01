# typed: true
# frozen_string_literal: true

class Redis::Client
  # Regex to parse Redit host strings into cluster + mode
  # Some example host strings used at this time in production:
  #
  # db-redis-rate-limiter-00-ro.service.github.net
  # db-redis-copilot-production.redis.cache.windows.net
  # db-redis-dotcom-staff-wus2-01.redis.cache.windows.net
  # db-redis-rate-limiter-01-rw.service.github.net
  # db-redis-redis102-rw.service.github.net

  REDIS_PREFIX = /db-redis/mi.freeze
  REDIS_SUFFIX = /(?:[\w\.]+)/mi.freeze
  REDIS_CONNECTION_ROLE = /(?:-(ro|rw))?/mi.freeze
  REDIS_CLUSTER = /([\w-]+?)/mi.freeze
  REDIS_HOST_PATTERN = /^#{REDIS_PREFIX}-#{REDIS_CLUSTER}#{REDIS_CONNECTION_ROLE}\.#{REDIS_SUFFIX}/mi.freeze

  # 10KB
  MINIMUM_COMMAND_SIZE = 1024 * 10

  # Up to 1_000 commands when calculating the size of a command
  # can take locally ~ 60 microseconds. We want to keep safe and
  # filter out commands that are too large, despite its unlikely
  # to happen in production.
  MAX_COMMAND_LENGTH_LIMIT_FOR_SIZE_CALCULATION = 1_000

  def cluster_info
    T.bind(self, ::Redis::Client)
    cluster, connection_role = host.match(REDIS_HOST_PATTERN)&.captures
    [cluster&.to_sym || :unknown, connection_role&.to_sym || :rw]
  end

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

  module RedisClientInstrumentation
    include GitHub::Memoizer
    include Kernel
    extend T::Helpers
    # Private: Value between 0 and 1 that is the sample rate for the metrics
    # produced by this class.
    STATS_SAMPLE_RATE = 0.5

    DOT = ".".freeze
    DASH = "-".freeze

    def initialize(options = {})
      @trace_command_size = options.delete(:trace_command_size)
      super(options)
    end

    def call(cmd, *args, &block)
      start = Time.now
      super
    rescue StandardError => e # rubocop:todo Lint/GenericRescue
      if command_name = build_command_name(cmd)
        GitHub.dogstats.increment("rpc.redis.error".freeze, tags: dogstats_tags(command_name) + ["error:#{e.class.name}"])
      end
      raise
    ensure
      duration = Time.now - T.cast(start, Time)
      duration_ms = duration * 1_000

      if command_name = build_command_name(cmd)
        tags = dogstats_tags(command_name)
        GitHub.dogstats.distribution("rpc.redis.dist.time".freeze, duration_ms, tags: tags)

        emit_redis_command_size_metric(command_name,
          cmd,
          "rpc.redis.dist.size",
          "rpc.redis.dist.size_overflow"
        )
      end

      if self.class.track
        self.class.queries << EventTrace.new(cmd, duration, args)
      end
      Redis::Client.query_time += duration
      Redis::Client.query_count += 1
    end

    def call_pipelined(cmd, *args, &block)
      start = Time.now
      super
    rescue StandardError => e # rubocop:todo Lint/GenericRescue
      GitHub.dogstats.increment("rpc.redis.error".freeze, tags: dogstats_tags("pipelined") + ["error:#{e.class.name}"])

      raise
    ensure
      duration = Time.now - T.cast(start, Time)
      duration_ms = duration * 1_000

      GitHub.dogstats.distribution("rpc.redis.dist.time".freeze, duration_ms, tags: dogstats_tags("pipelined"))

      cmd.commands.each do |command|
        command_name = build_command_name(command)
        tags = dogstats_tags(command_name)
        GitHub.dogstats.increment("rpc.redis.pipelined".freeze,
          sample_rate: STATS_SAMPLE_RATE,
          tags: tags)

        emit_redis_command_size_metric(command_name,
          command,
          "rpc.redis.dist.pipelined_size",
          "rpc.redis.pipelined_size_overflow",
          sample_rate: STATS_SAMPLE_RATE
        )
      end

      if self.class.track
        self.class.queries << EventTrace.new("(pipelined)", duration, cmd)
      end
      Redis::Client.query_time += duration
      Redis::Client.query_count += 1
    end

    def build_command_name(cmd)
      command_parts = Array(cmd)
      name = command_parts.first
      if name == :evalsha
        # return evalsha:script_sha
        return "#{name}:#{command_parts.second}"
      end
      name
    end

    def dogstats_tags(operation)
      T.bind(self, ::Redis::Client)
      cluster, connection_role = cluster_info

      tags = [
        "rpc_operation:#{operation}",
        "rpc_host:#{host}",
        "rpc_site:#{GitHub.site_from_host(host)}",
        "#{GitHub::TaggingHelper::CATALOG_SERVICE_TAG}:#{GitHub.context[:catalog_service] || "unknown"}",
      ]

      tags << (GitHub::DatadogTagsCache::REDIS_CLUSTER_NAMES[cluster] || "redis_cluster:#{cluster}")
      tags << (GitHub::DatadogTagsCache::REDIS_CONNECTION_ROLES[connection_role] || "connection_role:#{connection_role}")

      if GitHub.context[:remote_call_source_datadog_tags]
        tags.concat(GitHub.context[:remote_call_source_datadog_tags])
      else
        tags.push("source:unknown")
      end
    end

    def emit_redis_command_size_metric(command_name, cmd, metric, metric_overflow, sample_rate: nil)
      return unless @trace_command_size
      return unless command_name

      if FeatureFlag.vexi.enabled?(:emit_redis_command_size_metric, default: false)
        command_size = build_command_size(cmd)
        if command_size != -1 && command_size > minimum_command_size
          GitHub.dogstats.distribution(metric.freeze, command_size, tags: dogstats_tags(command_name))
        elsif command_size == -1
          GitHub.dogstats.increment(metric_overflow.freeze, tags: dogstats_tags(command_name), sample_rate: sample_rate)
        end
      end
    end

    def build_command_size(cmd)
      command_parts = Array(cmd)
      return -1 unless command_parts.length <= max_command_length_limit_for_size_calculation
      command_parts.select { |e| e.is_a?(String) }.map(&:bytesize).sum
    end

    memoize def minimum_command_size
      ENV.fetch("MINIMUM_COMMAND_SIZE", MINIMUM_COMMAND_SIZE).to_i
    end

    memoize def max_command_length_limit_for_size_calculation
      ENV.fetch("MAX_COMMAND_LENGTH_LIMIT_FOR_SIZE_CALCULATION", MAX_COMMAND_LENGTH_LIMIT_FOR_SIZE_CALCULATION).to_i
    end
  end

  if !GitHub::AppEnvironment.test?
    prepend RedisClientInstrumentation
  end
end
