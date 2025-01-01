# typed: false
# frozen_string_literal: true

module GitHub
  module Cache
    # Fake Memcache interface used by default in test environment. The Timid
    # mixin causes all get calls to return nil unless GitHub.cache.allow is set to a
    # Regexp specifying which keys return real cached values.
    class Fake
      include GitHub::Cache::Timid
      include GitHub::Cache::FakeAsync
      include GitHub::Cache::FakeConfig
      include GitHub::Cache::Failover
      include GitHub::Cache::Partition
      include GitHub::Cache::Zip
      include GitHub::Cache::Utils
      include GitHub::Cache::Skip
      include GitHub::Cache::DisableWrite
      include GitHub::Cache::HashKeys
      include GitHub::Cache::LongTTL

      attr_accessor :local

      def server_structs
        []
      end

      def namespace
        "fake"
      end

      def enable_local_cache
      end

      def stats
        {}
      end

      def local_hit_count
        0
      end
    end
  end
end
