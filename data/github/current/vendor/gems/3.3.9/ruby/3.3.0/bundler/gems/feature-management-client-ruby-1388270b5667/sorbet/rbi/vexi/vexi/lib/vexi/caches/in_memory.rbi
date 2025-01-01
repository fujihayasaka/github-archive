# frozen_string_literal: true
# typed: strict

module Vexi
  module Caches
    # Public: InMemory Cache definition.
    class InMemory
      extend T::Sig

      include Cache

      sig { void }
      def initialize; end

      sig do
        override.params(keys: T::Array[String]).returns(T.untyped)
      end
      def mget(keys); end

      sig do
        override.params(
          key: String
        ).returns(T.untyped)
      end
      def get(key); end

      sig { override.params(key_value_pairs: T::Hash[String, T.untyped], lifetime: Numeric).void }
      def mset(key_value_pairs, lifetime); end

      sig { override.params(key: String, value: T.untyped, lifetime: Numeric).void }
      def set(key, value, lifetime); end

      sig { override.returns(String) }
      def cache_name; end

      private

      sig { params(lifetime: Numeric).returns(Numeric) }
      def convert_lifetime(lifetime); end
    end
  end
end
