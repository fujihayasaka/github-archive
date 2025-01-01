# typed: true
# frozen_string_literal: true

module GitHub
  module Cache
    module ICache
      extend T::Sig
      extend T::Helpers
      interface!

      sig { abstract.params(key: String, raw: T::Boolean).returns(T.untyped) }
      def get(key, raw = false); end

      sig { abstract.params(key: String, value: T.untyped, ttl: Integer, raw: T::Boolean).returns(T.untyped) }
      def set(key, value, ttl = 0, raw = false); end

      sig { abstract.params(key: String, raw: T::Boolean).void }
      def delete(key, raw = false); end

      sig { abstract.params(servers: T.untyped).void }
      def reset(servers); end
    end
  end
end
