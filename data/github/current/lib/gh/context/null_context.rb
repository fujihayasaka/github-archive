# typed: strict
# frozen_string_literal: true

module GH
  module Context
    class NullContext
      # We don't want people relying on the GH::Context when it is not enabled but we don't want
      # it to be nilable either. So we raise an error if it is accessed.
      include Context

      MESSAGE = "GH::Context is not enabled! Please enable it by wrapping your code in GH::Context.enabled { ... }"

      sig { void }
      def initialize
        @identity_context = T.let(Auth::IdentityContext::ValueContext.new(nil), GH::Auth::IdentityContext)
        @domain_map = T.let(Hash.new { |h, k| h[k] = {} }, T::Hash[String, T::Hash[T::Module[T.anything], GH::Domain::Base]])
        @owner = T.let(NullOwnerContext.new.freeze, OwnerContext)
      end

      sig { override.returns(GH::Auth::IdentityContext) }
      def identity_context
        @identity_context
      end

      sig { override.params(ctx: GH::Auth::IdentityContext).void }
      def identity_context=(ctx)
        raise MESSAGE
      end

      sig { override.params(actor: T.nilable(GH::Auth::Actor), blk: T.nilable(T.proc.void)).void }
      def act_as(actor, &blk)
        raise MESSAGE
      end

      sig { override.params(namespace: T::Module[T.anything], constructor: T.proc.returns(GH::Domain::Base)).returns(GH::Domain::Base) }
      def domain(namespace, constructor)
        constructor.call
      end

      sig { override.params(namespace: T::Module[T.anything]).returns(T::Array[GH::Domain::Base]) }
      def all_domains_for(namespace)
        []
      end

      # no local caching for NullContext as it is effectively a singleton
      sig { override.returns(T.nilable(Concurrent::Hash)) }
      def remote_cache_registry
        nil
      end

      sig { override.returns(OwnerContext) }
      def owner
        @owner
      end

      sig { override.returns(T::Boolean) }
      def skip_remote_cache?
        false
      end

      sig { override.params(value: T::Boolean).void }
      def skip_remote_cache=(value)
        raise MESSAGE
      end

      private

      sig { override.returns(T::Hash[String, T::Hash[T::Module[T.anything], GH::Domain::Base]]) }
      attr_reader :domain_map
    end
  end
end
