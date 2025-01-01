# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "vexi/cache"

module FeatureFlag
  module Cache
    class Test
      extend T::Helpers
      include Vexi::Cache

      sig { void }
      def initialize
      end

      sig do
        params(
          keys: T::Array[String]
        ).returns(T::Array[T.untyped])
      end
      def mget(keys)
        []
      end

      sig { params(key: String).returns(T.untyped) }
      def get(key)
        nil
      end

      sig { params(key: String, value: T.untyped, lifetime: Numeric).void }
      def set(key, value, lifetime)
        nil
      end

      sig { params(key_value_pairs: T::Hash[String, T.untyped], lifetime: Numeric).void }
      def mset(key_value_pairs, lifetime)
        nil
      end

      sig { returns String }
      def cache_name
        "test"
      end
    end
  end
end
