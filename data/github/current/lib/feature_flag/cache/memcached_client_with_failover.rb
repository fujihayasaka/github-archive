# typed: strict
# frozen_string_literal: true

module FeatureFlag
  module Cache
    # A feature flag memcached client that supports failover.
    # Note: Make sure to include any non-failover changes made to this class in the non-failover version as well.
    class MemcachedClientWithFailover < MemcachedClient
      # NOTE: The order these mixins are included is important.

      if GitHub.foreground? || GitHub::AppEnvironment.test? || GitHub::AppEnvironment.development?
        prepend FeatureFlag::Cache::Instrumentation
      end

      # Mixin for Memcached::Rails that adds error swallowing and reliable server failover.
      include GitHub::Cache::Failover

      # Mixin for transparently compressing and decompressing values
      include FeatureFlag::Cache::LZ4

      # Mixin for truncating and hashing long keys.
      # This is a hard limit in the memcached client and will raise if the key exceeds 250 characters,
      # which includes the prefix_key / namespace.
      include GitHub::Cache::HashKeys

      # Mixin for disallowing long TTLs (longer than 30 day). We shouldn't need this for feature flags, but probably doesn't hurt to include it.
      include GitHub::Cache::LongTTL
    end
  end
end
