# typed: strict
# frozen_string_literal: true

require "github/cache"

module FeatureFlag
  module Cache
    # A feature flag memcached client that supports failover.
    # Note: Make sure to include any non-failover changes made to this class in the non-failover version as well.
    class MemcachedClient < ::Memcached::Rails
      extend T::Helpers
      abstract!

      include IMemcachedClient

      sig { returns(Symbol) }
      attr_reader :current_partition

      class << self
        delegate :query_time, :query_time=, :query_count, :query_count=,
                 :query_tracing, :query_tracing=, :query_sets, :query_sets=,
                 :query_hits, :query_hits=, :query_misses, :query_misses=,
                 :query_events, :query_events=, :track_events, :track_events=,
                 :distributed_tracing_enabled, :distributed_tracing_enabled=,
          to: :collector
      end

      sig { returns(T::Array[T.untyped]) }
      def self.query_keys
        [query_sets.keys, query_hits.keys, query_misses.keys].flatten.uniq.sort
      end

      sig { returns(GitHub::DataCollector::CacheInstrumenterCollector) }
      def self.collector
        GitHub::DataCollector::CacheInstrumenterCollector.get_instance "feature_flag_cache"
      end

      # The maximum number of servers to use for the feature flag cache, this must match the number of feature-flag-update-processor deployments
      sig { returns(Integer) }
      def self.max_server_count
        case GitHub::Config::Proxima.current_stamp_or_dotcom
        when "dotcom"; then 4       # per site
        when "prod-ae-01"; then 6   # per stamp for ae-01 in Proxima
        else; 3                     # per stamp for all other Proxima stamps
        end
      end

      sig { returns(T::Array[String]) }
      def self.servers
        all_servers = Array(cache_config[:servers])

        # If there are too many, truncate the list of servers to avoid exceeding max_server_count
        # This is to ensure that we are only using servers that are currently being updated by the feature flag update processor
        if all_servers.length > max_server_count
          GitHub.logger.warn("Feature flag memcached client configuration has too many servers configured", {
            "gh.cache.servers": all_servers.join(", "),
            "gh.cache.max_servers": max_server_count
          })
          GitHub.dogstats.increment("gh.feature_flag.cache.max_servers_exceeded", tags: ["max_count:#{max_server_count}", "actual_count:#{all_servers.length}"])

          all_servers = T.must(all_servers[0...max_server_count])
        end

        all_servers
      end

      sig { params(init_servers: T.nilable(T.any(String, T::Array[String]))).void }
      def initialize(init_servers = nil)
        config = self.class.cache_config
        config[:codec] = FeatureFlag::Cache::Codec

        namespace = "ff"
        namespace += if GitHub.employee_unicorn?
          GitHub.host_name[0..9]
        else
          GitHub::AppEnvironment.env
        end
        config[:namespace] = namespace
        config[:support_cas] = true

        # Read timeouts
        config[:timeout] = 0.02 # 20ms
        # Write timeouts
        config[:snd_timeout] = 0.25 # 250ms

        use_servers = init_servers ? Array(init_servers) : self.class.servers
        config[:servers] = use_servers

        @current_partition = T.let(:featureflag, Symbol)

        super(config)

        GitHub.logger.info("Initializing feature flag cache client", {
          "gh.cache.servers": use_servers.join(", "),
          "gh.cache.namespace": namespace
        })
      end

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def self.cache_config
        if GitHub.single_or_multi_tenant_enterprise? || GitHub.review_lab?
          GitHub::Cache::Config.new.for_partition(:global, sites: [GitHub.site])
        else
          GitHub::Cache::Config.new.for_partition(:featureflag, sites: [GitHub.site])
        end
      end

      sig { override.params(servers: T.untyped).void }
      def reset(servers = nil)
        super(servers)

        # Log the stats for informational purposes, but this is also being used to trigger a
        # connection to each of the cache servers to fetch the stats and ensure it is hot.
        GitHub.logger.info("Feature flag cache stats on reset", {
          "gh.cache.stats": stats.to_s
        })
      end

      sig { returns(T::Hash[T.any(Symbol, String), T.untyped]) }
      def stats
        # Disable stats in tests to avoid flakiness with mocks
        return {} if GitHub::AppEnvironment.test?
        begin
          super
        rescue ::Memcached::Error => e
          GitHub.logger.warn("Failed to get feature flag cache stats", {
            "exception.message": e.message,
            "exception.type": e.class.name,
            "exception.stacktrace": e.backtrace.to_s
          })

          {}
        end
      end
    end
  end
end
