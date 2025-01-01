# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "vexi/cache"

module FeatureFlag
  module Cache
    class Memcached
      extend T::Helpers
      include Vexi::Cache

      sig { params(cache_client: FeatureFlag::Cache::IMemcachedClient).void }
      def initialize(cache_client)
        @cache_client = cache_client
      end

      sig do
        params(
          keys: T::Array[String]
        ).returns(T::Array[T.untyped])
      end
      def mget(keys)
        @cache_client.get_multi(keys).values
      end

      sig do
        params(
          key: String
        ).returns(T.untyped)
      end
      def get(key)
        @cache_client.get(key)
      end

      sig { params(key_value_pairs: T::Hash[String, T.untyped], lifetime: Numeric).void }
      def mset(key_value_pairs, lifetime)
        key_value_pairs.each do |key, value|
          @cache_client.add(key, value, lifetime.to_i)
        end
        nil
      end

      sig { params(key: String, value: T.untyped, lifetime: Numeric).void }
      def set(key, value, lifetime)
        @cache_client.add(key, value, lifetime.to_i)
        nil
      end

      sig { returns String }
      def cache_name
        "memcached"
      end
    end
  end
end
