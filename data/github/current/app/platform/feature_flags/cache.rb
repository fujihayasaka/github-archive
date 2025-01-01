# typed: strict
# frozen_string_literal: true

require "lru_redux"

module Platform
  module FeatureFlags
    class Cache
      extend T::Sig
      CACHE_MAX_QUERIES = 1000

      @feature_flags_cache = T.let(nil, T.nilable(LruRedux::ThreadSafeCache))

      # Attempts to fetch the operation from the cache
      # returns nil if operation does not exist
      sig { params(query_hash: String).returns(T.nilable(T::Array[String])) }
      def self.fetch(query_hash)
        feature_flags_cache[query_hash] if feature_flags_cache.has_key?(query_hash)
      end

      sig { params(query_hash: String, flags: T::Array[Symbol]).void }
      def self.write(query_hash, flags)
        feature_flags_cache[query_hash] = flags
      end

      sig { returns(LruRedux::ThreadSafeCache) }
      def self.feature_flags_cache
        @feature_flags_cache ||= LruRedux::ThreadSafeCache.new(CACHE_MAX_QUERIES)
      end

      sig { returns(Integer) }
      def self.memsize
        feature_flags_cache.instance_variable_get(:@data).sum do |key, value|
          # reduced each value to the bytesize of the operation
          key.bytesize + value.reduce(0) { |sum, v| sum + v.bytesize }
        end
      end
    end
  end
end
