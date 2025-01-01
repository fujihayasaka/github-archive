# typed: strict
# frozen_string_literal: true

module FeatureFlag
  module Cache
    module IMemcachedClient
      extend T::Helpers
      interface!

      sig { abstract.params(key: String, raw: T::Boolean).returns(T.untyped) }
      def get(key, raw = false); end

      sig { abstract.params(keys: T::Array[String], raw: T::Boolean).returns(T::Hash[String, T.untyped]) }
      def get_multi(keys, raw = false); end

      sig { abstract.params(key: String, value: T.untyped, ttl: Integer, raw: T::Boolean).returns(T::Boolean) }
      def set(key, value, ttl = 0, raw = false); end

      sig { abstract.params(key: String, value: T.untyped, ttl: Integer, raw: T::Boolean).returns(T.nilable(T::Boolean)) }
      def add(key, value, ttl = 0, raw = false); end

      sig { abstract.params(key: String, ttl: Integer, raw: T::Boolean, block: T.proc.params(value: T.untyped).returns(T.untyped)).returns(T.nilable(T::Boolean)) }
      def cas(key, ttl = 0, raw = false, &block); end

      sig { abstract.params(key: String, raw: T::Boolean).returns(T::Boolean) }
      def delete(key, raw = false); end

      sig { abstract.params(servers: T.untyped).void }
      def reset(servers = nil); end
    end
  end
end
