# typed: strict
# frozen_string_literal: true

module GH
  module Context
    class DefaultContext
      include Context

      sig { void }
      def initialize
        @identity_context = T.let(Auth::IdentityContext::ValueContext.new(nil), GH::Auth::IdentityContext)
        @domain_map = T.let(Hash.new { |h, k| h[k] = {} }, T::Hash[String, T::Hash[Module, GH::Domain::Base]])
      end

      sig { params(ctx: GH::Auth::IdentityContext).void }
      def identity_context=(ctx)
        @identity_context = ctx
      end

      sig { override.returns(GH::Auth::IdentityContext) }
      def identity_context
        @identity_context
      end

      sig do
        override.params(
        namespace: Module,
        constructor: T.proc.returns(GH::Domain::Base)
        ).returns(GH::Domain::Base)
      end
      def domain(namespace, constructor)
        T.must(@domain_map[identity_context.hash_key])[namespace] ||= constructor.call
      end
    end
  end
end
