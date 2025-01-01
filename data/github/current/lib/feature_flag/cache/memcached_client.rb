# typed: strict
# frozen_string_literal: true

module FeatureFlag
  module Cache
    # A feature flag memcached client that supports failover.
    # Note: Make sure to include any non-failover changes made to this class in the non-failover version as well.
    class MemcachedClient < ::Memcached::Rails
      extend T::Sig
      extend T::Helpers
      abstract!

      include IMemcachedClient
      include GitHub::Cache::ICacheConfig # Required for including GitHub::Cache::HashKeys

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

      sig { returns(T.untyped) }
      def self.collector
        GitHub::DataCollector::CacheInstrumenterCollector.get_instance "feature_flag_cache"
      end

      sig { params(init_servers: T.nilable(T.any(String, T::Array[String]))).void }
      def initialize(init_servers = nil)
        super(GitHub.cache_config)

        ff_servers = init_servers ||
          # Use the servers from the feature flag partition if available, otherwise use the global servers
          (GitHub.partition_config[:featureflag] ? GitHub.partition_config[:featureflag]["servers"] : GitHub.cache_config[:servers])

        set_servers ff_servers
        reset ff_servers
      end
    end
  end
end
