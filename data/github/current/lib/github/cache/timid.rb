# typed: true
# frozen_string_literal: true

module GitHub
  module Cache
    # Cache mixin replaces memcached network calls with a local in process
    # hash. Used in testing environments only. Doesn't implement any _async
    # variants, mixin FakeAsync to do that.
    module Timid
      extend T::Helpers
      include GitHub::Cache::ICache

      requires_ancestor { GitHub::Cache::ICacheConfig }

      # Regexp dictating which cache keys return values from get calls. This is
      # nil by default, causing all gets to return nil. Set to /.*/ to allow all
      # cache gets.
      attr_accessor :allow

      def store
        @store ||= {}
      end

      def get(key, raw = false)
        return nil unless key =~ allow
        if value = store[key]
          raw ? value : GitHub::Cache::Codec.unpack(value)
        end
      end

      def get_multi(keys, raw = false)
        ret = {}
        keys.each do |key|
          next unless key =~ allow
          if store.key?(key)
            ret[key] = raw ? store[key] : GitHub::Cache::Codec.unpack(store[key])
          end
        end
        ret
      end

      def set(key, value, ttl = 0, raw = false)
        cache_value = raw ? value : GitHub::Cache::Codec.pack(value)
        if value_too_big?(cache_value)
          nil
        else
          store[key] = cache_value
          true
        end
      end

      def add(key, value, ttl = 0, raw = false)
        return true unless key =~ allow
        return if store.key?(key)
        cache_value = raw ? value : GitHub::Cache::Codec.pack(value)
        if value_too_big?(cache_value)
          nil
        else
          store[key] = cache_value
          true
        end
      end

      def incr(key, value = 1)
        return nil unless key =~ allow
        store[key] = store[key].to_i + value if store.key?(key)
      end

      def decr(key, value = 1)
        return nil unless key =~ allow
        store[key] = store[key].to_i - value if store.key?(key)
      end

      def clear
        @store = {}
      end

      def delete(key, raw = false)
        store.delete(key)
      end

      def exist?(key, options = nil)
        store.key?(key)
      end

      def reset(servers)
      end

      def value_too_big?(value)
        value.respond_to?(:bytesize) && value.bytesize > GitHub::Cache::Failover::MAX_VALUE_SIZE
      end

      def size
        store.reduce(0) { |sum, (k, _)| allow.match?(k) ? sum + 1 : sum }
      end

      include GitHub::Cache::WithoutMixins
    end
  end
end
