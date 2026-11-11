# typed: true
# frozen_string_literal: true

module Search
  # A self-requeuing job that periodically samples health signals from MySQL
  # and Elasticsearch, appending each reading to a fixed-length Redis list
  # (one list per service/entity/signal). After each append it emits Datadog
  # rate-of-change gauges over 5, 10, and 15-minute windows so that dependent
  # jobs (RepairJob, ReindexJob) can make throttle decisions without baked-in
  # numeric thresholds.
  #
  # Redis key format: gh.search.indexing.auto_throttle.data.<service>.<entity>.<signal>
  # Each key holds up to MAX_SAMPLES float values (newest last).
  #
  # Signals sampled:
  #   elasticsearch.<cluster>: health_status (string, stored only), thread_pool_rejections, available (1/0)
  #   mysql.<cluster>:        replication_delay_secs, query_latency
  class SearchIndexingAutoThrottleDeciderJob < ApplicationJob
    REDIS_BASE_PREFIX        = "gh.search.indexing.auto_throttle"
    RUNNING_INDICATOR_KEY    = "#{REDIS_BASE_PREFIX}.running"
    REDIS_DATA_KEY_PREFIX    = "#{REDIS_BASE_PREFIX}.data"
    REDIS_TTL                = 1800 # 30 min — well beyond the 15-sample window
    MAX_SAMPLES              = 16   # 15 one-minute intervals of lookback
    REQUEUE_INTERVAL_SECONDS = 60

    RATE_OF_CHANGE_WINDOWS = T.let([5, 10, 15].freeze, T::Array[Integer])

    queue_as :search_indexing_auto_throttle
    retry_on_dirty_exit

    include GitHub::ServiceMapping

    sig { void }
    def perform
      set_running_indicator
      record_elasticsearch_signals
      record_mysql_signals
      clean_running_indicator unless self.class.enabled?
      requeue_self if self.class.enabled?
    end

    sig { returns(T::Boolean) }
    def self.enabled?
      # Defaulting to `true` so that if there are problems with Vexi evaluation,
      # we won't have a gap in our metrics. Since this only runs one worker
      # every minute, this is low-risk.
      FeatureFlag.vexi.enabled?(:elastomer_index_auto_throttle_decider_job, default: true)
    end

    sig { returns(T::Boolean) }
    def self.running?
      GitHub.legacy_redis.exists(RUNNING_INDICATOR_KEY) == 1
    end

    # External callers can request this job to start. If the job is already running, nothing happens.
    # If the job is disabled, nothing happens.
    def self.request_start
      return unless enabled?  # Don't start if explicitly disabled
      return if running?      # Don't enqueue if already known to be running
      return if queue_depth > 0  # Don't enqueue if there are already enqueued jobs that haven't started yet
      GitHub.logger.info("Enqueueing #{self.name} because it was requested to start and is not currently running.")
      perform_later
    end

    private

    sig { void }
    def record_elasticsearch_signals
      available_clusters = Elastomer.router.available_clusters
      Elastomer.router.clusters.each do |cluster_name|
        store_signal("elasticsearch", cluster_name, "health_status",
          fetch_cluster_health_status(cluster_name))
        record_signal("elasticsearch", cluster_name, "thread_pool_rejections",
          fetch_write_thread_pool_rejections(cluster_name))
        record_signal("elasticsearch", cluster_name, "available",
          available_clusters.include?(cluster_name) ? 1 : 0)
      end
    end

    sig { void }
    def record_mysql_signals
      mysql_cluster_names.each do |cluster_name|
        record_signal("mysql", cluster_name.to_s, "replication_delay_secs",
          fetch_replication_delay(cluster_name))
        record_signal("mysql", cluster_name.to_s, "query_latency",
          fetch_query_latency(cluster_name))
      end
    end

    sig { params(cluster_name: String).returns(String) }
    def fetch_cluster_health_status(cluster_name)
      Elastomer.router.client(cluster_name).cluster.health.fetch("status", "unknown")
    rescue ElastomerClient::Client::Error => e
      Failbot.report(e, cluster: cluster_name)
      GitHub.dogstats.increment("search.auto_throttle.es.cluster_health.error", tags: ["cluster:#{cluster_name}"])
      "unknown"
    end

    sig { params(cluster_name: String).returns(Integer) }
    def fetch_write_thread_pool_rejections(cluster_name)
      stats = Elastomer.router.client(cluster_name).nodes.stats(stats: "thread_pool")
      nodes = stats.fetch("nodes", {})
      total_rejected = nodes.sum do |_node_id, node|
        pools = node.fetch("thread_pool", {})
        write_pool = pools["write"]
        write_pool.fetch("rejected", 0).to_i
      end
      total_rejected
    rescue ElastomerClient::Client::Error => e
      Failbot.report(e, cluster: cluster_name)
      GitHub.dogstats.increment("search.auto_throttle.es.thread_pool_rejections.error", tags: ["cluster:#{cluster_name}"])
      0
    end

    # A layer of abstraction only present because in test, it was difficult to reliably
    # mock/stub Freno.client due to a memoization decorator deep in Freno::Client.
    # This allows us to stub with our own client in tests without worrying about this.
    sig { returns(Freno::Client) }
    def freno
      Freno.client # Already memoized by Freno module
    end

    sig { params(mysql_cluster: Symbol).returns(Float) }
    def fetch_replication_delay(mysql_cluster)
      delay = freno.replication_delay(app: "github", store_name: mysql_cluster).to_f
      delay
    rescue Freno::Error => e
      Failbot.report(e, cluster: mysql_cluster)
      GitHub.dogstats.increment("search.auto_throttle.mysql.replication_delay.error", tags: ["cluster:#{mysql_cluster}"])
      0.0
    end

    sig { params(cluster_name: Symbol).returns(Float) }
    def fetch_query_latency(cluster_name)
      query = "avg:rpc.mysql.dist.time{cluster:#{cluster_name}}"
      to    = Time.now
      from  = to - REQUEUE_INTERVAL_SECONDS.seconds
      status, results = GitHub.dogapi.get_points(query, from, to)
      return 0.0 unless status == "200" && results["series"].present?

      _, value = results["series"].first&.dig("pointlist")&.last
      value.to_f
    rescue RuntimeError => e
      Failbot.report(e, cluster: cluster_name)
      GitHub.dogstats.increment("search.auto_throttle.mysql.query_latency.error", tags: ["cluster:#{cluster_name}"])
      0.0
    end

    RECORD_SIGNAL_SCRIPT = T.let(<<~LUA.freeze, String)
      redis.call('RPUSH', KEYS[1], ARGV[1])
      redis.call('LTRIM', KEYS[1], -ARGV[2], -1)
      redis.call('EXPIRE', KEYS[1], ARGV[3])
      return redis.call('LRANGE', KEYS[1], 0, -1)
    LUA

    sig { params(service: String, entity: String, signal: String, value: T.untyped).void }
    def store_signal(service, entity, signal, value)
      key = data_redis_key(service, entity, signal)
      GitHub.legacy_redis.eval(
        RECORD_SIGNAL_SCRIPT,
        keys: [key],
        argv: [value.to_s, MAX_SAMPLES, REDIS_TTL],
      )
    end

    sig { params(service: String, entity: String, signal: String, value: Numeric).void }
    def record_signal(service, entity, signal, value)
      key = data_redis_key(service, entity, signal)
      raw = GitHub.legacy_redis.eval(
        RECORD_SIGNAL_SCRIPT,
        keys: [key],
        argv: [value.to_s, MAX_SAMPLES, REDIS_TTL],
      )
      samples = raw.map(&:to_f)
      emit_rate_of_change(samples, service: service, entity: entity, signal: signal)
    end

    sig { params(service: String, entity: String, signal: String).returns(String) }
    def data_redis_key(service, entity, signal)
      "#{REDIS_DATA_KEY_PREFIX}.#{service}.#{entity}.#{signal}"
    end

    sig { params(samples: T::Array[Float], service: String, entity: String, signal: String).void }
    def emit_rate_of_change(samples, service:, entity:, signal:)
      base_tags = ["signal:#{signal}", "service:#{service}", "entity:#{entity}"]
      RATE_OF_CHANGE_WINDOWS.each do |window|
        next if samples.length <= window

        oldest = samples[samples.length - window - 1]
        newest = samples.last
        next unless oldest && newest

        GitHub.dogstats.gauge(
          "search.indexing.auto_throttle.rate_of_change",
          (newest - oldest) / window,
          tags: base_tags + ["samples:#{window}"],
        )
      end
    end

    sig { returns(T::Array[Symbol]) }
    def mysql_cluster_names
      Elastomer::Adapter.subclasses.map(&:mysql_cluster).uniq
    end

    sig { void }
    def requeue_self
      return unless self.class.enabled?
      self.class.set(wait: REQUEUE_INTERVAL_SECONDS.seconds).perform_later
    end

    sig { void }
    def clean_running_indicator
      GitHub.legacy_redis.del(RUNNING_INDICATOR_KEY)
    end

    def set_running_indicator
      GitHub.legacy_redis.setex(RUNNING_INDICATOR_KEY, REDIS_TTL, true)
    end
  end
end
