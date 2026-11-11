# typed: strict
# frozen_string_literal: true

module GH
  module Context
    class DefaultContext
      include Context

      sig { void }
      def initialize
        @identity_context = T.let(Auth::IdentityContext::ValueContext.new(nil), GH::Auth::IdentityContext)
        @domain_map = T.let(Hash.new { |h, k| h[k] = {} }, T::Hash[String, T::Hash[T::Module[T.anything], GH::Domain::Base]])
        @remote_cache_registry = T.let(Concurrent::Hash.new, T.nilable(Concurrent::Hash))
        @owner = T.let(OwnerContext.new, OwnerContext)
        @skip_remote_cache = T.let(false, T::Boolean)
      end

      sig { override.params(ctx: GH::Auth::IdentityContext).void }
      def identity_context=(ctx)
        @identity_context = ctx
      end

      sig { override.returns(GH::Auth::IdentityContext) }
      def identity_context
        @identity_context
      end

      sig { override.params(actor: T.nilable(GH::Auth::Actor), blk: T.nilable(T.proc.void)).void }
      def act_as(actor, &blk)
        ctx = GH::Auth::IdentityContext::ValueContext.new(actor)
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
        constructor: T.proc.returns(GH::Domain::Base)
        ).returns(GH::Domain::Base)
      end
      def domain(namespace, constructor)
        T.must(@domain_map[identity_context.hash_key])[namespace] ||= constructor.call
      end

      sig { override.params(namespace: T::Module[T.anything]).returns(T::Array[GH::Domain::Base]) }
      def all_domains_for(namespace)
        @domain_map.collect { |_, domains| domains[namespace] }.compact
      end

      sig { override.returns(T.nilable(Concurrent::Hash)) }
      attr_reader :remote_cache_registry

      sig { override.returns(OwnerContext) }
      attr_reader :owner

      sig { override.returns(T::Boolean) }
      def skip_remote_cache?
        @skip_remote_cache
      end

      sig { override.params(value: T::Boolean).void }
      def skip_remote_cache=(value)
        @skip_remote_cache = value
      end

      private

      sig { override.returns(T::Hash[String, T::Hash[T::Module[T.anything], GH::Domain::Base]]) }
      attr_reader :domain_map
    end
  end
end
