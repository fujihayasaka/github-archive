# typed: strict
# frozen_string_literal: true

module OctoCore
  module Context
    class DefaultContext
      extend T::Sig
      include Context

      sig { void }
      def initialize
        @identity_context = T.let(Auth::IdentityContext::ValueContext.new(nil), OctoCore::Auth::IdentityContext)
        @domain_map = T.let(Hash.new { |h, k| h[k] = {} }, T::Hash[String, T::Hash[T::Module[T.anything], OctoCore::Domain::Base]])
        @stash = T.let({}, T::Hash[Symbol, T.untyped])
      end

      sig { override.returns(T::Hash[Symbol, T.untyped]) }
      attr_reader :stash

      sig { override.returns(OctoCore::Auth::IdentityContext) }
      attr_accessor :identity_context

      sig { override.params(actor: T.nilable(OctoCore::Auth::Actor), blk: T.nilable(T.proc.void)).void }
      def act_as(actor, &blk)
        ctx = OctoCore::Auth::IdentityContext::ValueContext.new(actor)
        scoped_context = block_given?

        if scoped_context
          begin
            previous_context = identity_context
            self.identity_context = ctx
            yield
          ensure
            self.identity_context = previous_context if previous_context
          end
        else
          self.identity_context = ctx
        end
      end

      sig do
        override.params(
          namespace: T::Module[T.anything],
          constructor: T.proc.returns(OctoCore::Domain::Base)
        ).returns(OctoCore::Domain::Base)
      end
      def domain(namespace, constructor)
        T.must(@domain_map[identity_context.hash_key])[namespace] ||= constructor.call
      end
    end
  end
end
