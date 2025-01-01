# typed: true
# frozen_string_literal: true

module GitHub
  module Cache
    module IAsyncCache
      extend T::Sig
      extend T::Helpers
      interface!

      sig { abstract.params(key: String, raw: T::Boolean).returns(Promise[T.untyped]) }
      def async_get(key, raw = false); end

      sig { abstract.params(key: String, value: T.untyped, ttl: Integer, raw: T::Boolean).returns(Promise[T.untyped]) }
      def async_set(key, value, ttl = 0, raw = false); end

      sig { abstract.params(key: String, raw: T::Boolean).returns(Promise[T.untyped]) }
      def async_delete(key, raw = false); end
    end
  end
end
