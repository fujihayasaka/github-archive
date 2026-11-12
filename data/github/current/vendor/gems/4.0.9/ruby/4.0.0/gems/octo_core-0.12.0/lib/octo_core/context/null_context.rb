# typed: strict
# frozen_string_literal: true

module OctoCore
  module Context
    class NullContext
      extend T::Sig

      # We don't want people relying on the OctoCore::Context when it is not enabled but we don't want
      # it to be nilable either. So we raise an error if it is accessed.
      include Context

      MESSAGE = "OctoCore::Context is not enabled! Please enable it by wrapping your code in OctoCore::Context.enabled { ... }"

      sig { override.returns(T::Hash[Symbol, T.untyped]) }
      def stash
        raise MESSAGE
      end

      sig { override.returns(OctoCore::Auth::IdentityContext) }
      def identity_context
        raise MESSAGE
      end

      sig { override.params(ctx: OctoCore::Auth::IdentityContext).void }
      def identity_context=(ctx)
        raise MESSAGE
      end

      sig { override.params(actor: T.nilable(OctoCore::Auth::Actor), blk: T.nilable(T.proc.void)).void }
      def act_as(actor, &blk)
        raise MESSAGE
      end

      sig { override.params(namespace: T::Module[T.anything], constructor: T.proc.returns(OctoCore::Domain::Base)).returns(OctoCore::Domain::Base) }
      def domain(namespace, constructor)
        raise MESSAGE
      end
    end
  end
end
