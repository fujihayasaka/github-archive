# typed: true
# frozen_string_literal: true

module GitHub
  module DataCollector
    autoload :AuthzdCollector,               "github/data_collector/authzd_collector"
    autoload :Collector,                     "github/data_collector/collector"
    autoload :CacheInstrumenterCollector,    "github/data_collector/cache_instrumenter_collector"
    autoload :FrenoInstrumenterCollector,    "github/data_collector/freno_instrumenter_collector"
    autoload :GCStatsCollector,              "github/data_collector/gc_stats_collector"
    autoload :YJITStatsCollector,            "github/data_collector/yjit_stats_collector"
    autoload :GitRPCInstrumenterCollector,   "github/data_collector/gitrpc_instrumenter_collector"
    autoload :GracefulDegradationCollector,  "github/data_collector/graceful_degradation_collector"
    autoload :HTMLPipelineInstrumenterCollector, "github/data_collector/html_pipeline_instrumenter_collector"
    autoload :JobInstrumenterCollector,      "github/data_collector/job_instrumenter_collector"
    autoload :MemcacheInstrumenterCollector, "github/data_collector/memcache_instrumenter_collector"
    autoload :MysqlInstrumenterCollector,    "github/data_collector/mysql_instrumenter_collector"
    autoload :PlatformGlobalScopeCollector,  "github/data_collector/platform_global_scope_collector"
    autoload :RedisInstrumenterCollector,    "github/data_collector/redis_instrumenter_collector"
    autoload :SpokesdInstrumenterCollector,  "github/data_collector/spokesd_instrumenter_collector"

    def self.collectors
      if collectors = collector_thread[:data_collectors]
        collectors
      else
        collector_thread[:data_collectors] = {}
      end
    end

    def self.reset_all
      collectors.values.each(&:reset)
    end

    def self.enable_all
      collector_thread[:data_collectors_enabled] = true
      collectors.values.each(&:enable)
    end

    def self.enable_by_default?
      collector_thread[:data_collectors_enabled]
    end

    def self.collector_thread
      Thread.current[:data_collector_thread] ||= Thread.current
    end

    def self.with_collector_thread(new_collector_thread)
      previous_collector_thread = Thread.current[:data_collector_thread]
      Thread.current[:data_collector_thread] = new_collector_thread
      yield
    ensure
      Thread.current[:data_collector_thread] = previous_collector_thread
    end
  end
end
