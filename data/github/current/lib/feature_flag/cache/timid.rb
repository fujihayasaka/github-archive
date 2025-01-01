# typed: strict
# frozen_string_literal: true

module FeatureFlag
  module Cache
    # Cache mixin replaces memcached network calls with a local in process
    # hash. Used in testing environments only.
    module Timid
      extend T::Helpers
      include FeatureFlag::Cache::IMemcachedClient

      # Regexp dictating which cache keys return values from get calls. This is
      # nil by default, causing all gets to return nil. Set to /.*/ to allow all
      # cache gets.

      sig { returns(T.nilable(Regexp)) }
      attr_reader :allow

      sig { params(allow: T.nilable(Regexp)).void }
      attr_writer :allow

      sig { void }
      def initialize
        @allow = T.let(nil, T.nilable(Regexp))
      end

      sig { returns(T::Hash[String, T.untyped]) }
      def store
        @store ||= T.let({}, T.nilable(T::Hash[String, T.untyped]))
      end

      sig { override.params(key: String, raw: T::Boolean).returns(T.untyped) }
      def get(key, raw = false)
        return nil unless key =~ allow
        if value = store[key]
          raw ? value : FeatureFlag::Cache::MsgPack.unpack(value)
        end
      end

      sig { override.params(keys: T::Array[String], raw: T::Boolean).returns(T::Hash[String, T.untyped]) }
      def get_multi(keys, raw = false)
        ret = {}
        keys.each do |key|
          next unless key =~ allow
          if store.key?(key)
            ret[key] = raw ? store[key] : FeatureFlag::Cache::MsgPack.unpack(store[key])
          end
        end
        ret
      end

      sig { override.params(key: String, value: T.untyped, ttl: Integer, raw: T::Boolean).returns(T::Boolean) }
      def set(key, value, ttl = 0, raw = false)
        cache_value = raw ? value : FeatureFlag::Cache::MsgPack.pack(value)
        if value_too_big?(cache_value)
          false
        else
          store[key] = cache_value
          true
        end
      end

      sig { override.params(key: String, value: T.untyped, ttl: Integer, raw: T::Boolean).returns(T.nilable(T::Boolean)) }
      def add(key, value, ttl = 0, raw = false)
        return true unless key =~ allow
        return if store.key?(key)
        cache_value = raw ? value : FeatureFlag::Cache::MsgPack.pack(value)
        if value_too_big?(cache_value)
          nil
        else
          store[key] = cache_value
          true
        end
      end

      sig { override.params(key: String, ttl: Integer, raw: T::Boolean, block: T.proc.params(value: T.untyped).returns(T.untyped)).returns(T.nilable(T::Boolean)) }
      def cas(key, ttl = 0, raw = false, &block)
        value = get(key, raw)
        value = yield value
        set(key, value, ttl, raw)
      end

      sig { void }
      def clear
        @store = {}
      end

      sig { override.params(key: String, raw: T::Boolean).returns(T::Boolean) }
      def delete(key, raw = false)
        result = store.delete(key)
        !!result
      end

      sig { params(key: String, options: T.untyped).returns(T::Boolean) }
      def exist?(key, options = nil)
        store.key?(key)
      end

      sig { params(value: T.untyped).returns(T::Boolean) }
      def value_too_big?(value)
        value.respond_to?(:bytesize) && value.bytesize > GitHub::Cache::Failover::MAX_VALUE_SIZE
      end

      sig { override.params(servers: T.untyped).void }
      def reset(servers = [])
      end
    end
  end
end
