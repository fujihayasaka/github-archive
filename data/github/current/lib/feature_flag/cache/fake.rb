# typed: false
# frozen_string_literal: true

module FeatureFlag
  module Cache
    # Fake Memcache interface used by default in test environment. The Timid
    # mixin causes all get calls to return nil unless `allow` is set on the client to a
    # Regexp specifying which keys return real cached values.
    class Fake
      include IMemcachedClient

      include FeatureFlag::Cache::Timid
      include FeatureFlag::Cache::LZ4
      include GitHub::Cache::HashKeys
      include GitHub::Cache::LongTTL


      def namespace
        "fake"
      end

      def logger; end

      def logger=(logger); end

      def options
        {}
      end

      def prefix_key
        namespace
      end

      def server_by_key(key)
        nil
      end

      def set_servers(servers)
      end

      def reset(servers = [])
      end
    end
  end
end
