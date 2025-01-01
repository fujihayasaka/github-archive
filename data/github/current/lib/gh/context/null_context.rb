# typed: strict
# frozen_string_literal: true

module GH
  module Context
    class NullContext
      # We don't want people relying on the GH::Context when it is not enabled but we don't want
      # it to be nilable either. So we raise an error if it is accessed.
      include Context

      MESSAGE = "GH::Context is not enabled! Please enable it by wrapping your code in GH::Context.enabled { ... }"

      sig { override.returns(GH::Auth::IdentityContext) }
      def identity_context
        raise MESSAGE
      end

      sig { override.params(namespace: Module, constructor: T.proc.returns(GH::Domain::Base)).returns(GH::Domain::Base) }
      def domain(namespace, constructor)
        raise MESSAGE
      end
    end
  end
end
