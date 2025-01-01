# typed: strict
# frozen_string_literal: true

module FeatureFlag
  module Cache
    module IMemcachedClient
      extend T::Sig
      extend T::Helpers
      interface!

      sig { abstract.params(key: String, raw: T::Boolean).returns(T.untyped) }
      def get(key, raw = false); end

      sig { abstract.params(keys: T::Array[String], raw: T::Boolean).returns(T::Hash[String, T.untyped]) }
      def get_multi(keys, raw = false); end

      sig { abstract.params(key: String, value: T.untyped, ttl: Integer, raw: T::Boolean).returns(T.untyped) }
      def set(key, value, ttl = 0, raw = false); end

      sig { abstract.params(key: String, value: T.untyped, ttl: Integer, raw: T::Boolean).returns(T.untyped) }
      def add(key, value, ttl = 0, raw = false); end

      sig { abstract.params(key: String, raw: T::Boolean).void }
      def delete(key, raw = false); end
    end
  end
end
