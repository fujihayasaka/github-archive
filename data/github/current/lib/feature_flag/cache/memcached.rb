# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "vexi/cache"

module FeatureFlag
  module Cache
    class Memcached
      extend T::Helpers
      include Vexi::Cache

      sig { params(cache_client: FeatureFlag::Cache::IMemcachedClient, proxy_read_client: T.nilable(FeatureFlag::Cache::IMemcachedClient)).void }
      def initialize(cache_client, proxy_read_client: nil)
        @cache_client = cache_client
        @proxy_read_client = proxy_read_client
      end

      sig do
        params(
          keys: T::Array[String]
        ).returns(T::Array[T.untyped])
      end
      def mget(keys)
        read_client.get_multi(keys).values
      end

      sig do
        params(
          key: String
        ).returns(T.untyped)
      end
      def get(key)
        read_client.get(key)
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

      private

      sig { returns(FeatureFlag::Cache::IMemcachedClient) }
      def read_client
        if @proxy_read_client && GitHub.kube? && ENV["FEATUREFLAG_MEMCACHED_PROXY_READS_ENABLED"] == "true"
          @proxy_read_client
        else
          @cache_client
        end
      end
    end
  end
end
