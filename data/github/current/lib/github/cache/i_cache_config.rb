# typed: true
# frozen_string_literal: true

module GitHub
  module Cache
    module ICacheConfig
      extend T::Sig
      extend T::Helpers
      interface!

      sig { abstract.returns(T.untyped) }
      def logger; end

      sig { abstract.params(servers: T.untyped).void }
      def set_servers(servers); end

      sig { abstract.params(key: String).returns(T.untyped) }
      def server_by_key(key); end

      sig { abstract.returns(T::Hash[T.untyped, T.untyped]) }
      def options; end

      sig { abstract.returns(T.nilable(String)) }
      def prefix_key; end
    end
  end
end
